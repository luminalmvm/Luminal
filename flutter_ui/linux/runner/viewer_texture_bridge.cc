#include "viewer_texture_bridge.h"

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <unistd.h>

#include <cstdint>

// ---------------------------------------------------------------------------
// The DMA-BUF-backed FlTextureGL subclass.
//
// One instance per registered engine texture. It holds the DMA-BUF metadata the
// engine reported; the EGLImage + GL texture are created lazily on the first
// `populate` (that is the only moment the GL context is guaranteed current, on
// the render thread). The engine re-uses one texture across frames, so this is
// imported once and then just re-sampled on each `frameReady`.
// ---------------------------------------------------------------------------

G_DECLARE_FINAL_TYPE(LumitDmabufTexture, lumit_dmabuf_texture, LUMIT,
                     DMABUF_TEXTURE, FlTextureGL)

struct _LumitDmabufTexture {
  FlTextureGL parent_instance;

  // The DMA-BUF the engine exported (owned here until the texture is disposed).
  int fd;
  uint32_t width;
  uint32_t height;
  uint32_t stride;
  uint32_t offset;
  uint32_t fourcc;
  uint64_t modifier;

  // Lazily created on the first populate (render thread, GL context current).
  gboolean created;
  gboolean failed;
  GLuint gl_texture;
  EGLImageKHR egl_image;
};

G_DEFINE_TYPE(LumitDmabufTexture, lumit_dmabuf_texture, fl_texture_gl_get_type())

// Import the DMA-BUF into an EGLImage and bind it to a fresh GL texture. Runs on
// the render thread with the Flutter GL context current (called from populate).
// Returns FALSE and sets |error| on failure, so the engine drops the frame and
// Dart falls back to the read-back path.
static gboolean lumit_dmabuf_texture_create(LumitDmabufTexture* self,
                                            GError** error) {
  static PFNEGLCREATEIMAGEKHRPROC create_image =
      reinterpret_cast<PFNEGLCREATEIMAGEKHRPROC>(
          eglGetProcAddress("eglCreateImageKHR"));
  static PFNGLEGLIMAGETARGETTEXTURE2DOESPROC image_target_texture =
      reinterpret_cast<PFNGLEGLIMAGETARGETTEXTURE2DOESPROC>(
          eglGetProcAddress("glEGLImageTargetTexture2DOES"));
  if (create_image == nullptr || image_target_texture == nullptr) {
    g_set_error(error, g_quark_from_static_string("lumit"), 0,
                "EGL dma-buf import extensions are unavailable");
    return FALSE;
  }

  EGLDisplay display = eglGetCurrentDisplay();
  if (display == EGL_NO_DISPLAY) {
    g_set_error(error, g_quark_from_static_string("lumit"), 0,
                "no current EGL display in the populate callback");
    return FALSE;
  }

  // The EGL_LINUX_DMA_BUF_EXT attribute list (mirrors the reference plugin). The
  // modifier attributes are appended only for a non-linear buffer; the engine's
  // linear-tiling path reports modifier 0, so they are usually omitted.
  EGLint attribs[30];
  int i = 0;
  attribs[i++] = EGL_LINUX_DRM_FOURCC_EXT;
  attribs[i++] = static_cast<EGLint>(self->fourcc);
  attribs[i++] = EGL_WIDTH;
  attribs[i++] = static_cast<EGLint>(self->width);
  attribs[i++] = EGL_HEIGHT;
  attribs[i++] = static_cast<EGLint>(self->height);
  attribs[i++] = EGL_DMA_BUF_PLANE0_FD_EXT;
  attribs[i++] = self->fd;
  attribs[i++] = EGL_DMA_BUF_PLANE0_OFFSET_EXT;
  attribs[i++] = static_cast<EGLint>(self->offset);
  attribs[i++] = EGL_DMA_BUF_PLANE0_PITCH_EXT;
  attribs[i++] = static_cast<EGLint>(self->stride);
  if (self->modifier != 0) {
    attribs[i++] = EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT;
    attribs[i++] = static_cast<EGLint>(self->modifier & 0xFFFFFFFF);
    attribs[i++] = EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT;
    attribs[i++] = static_cast<EGLint>(self->modifier >> 32);
  }
  attribs[i++] = EGL_NONE;

  EGLImageKHR image = create_image(display, EGL_NO_CONTEXT,
                                   EGL_LINUX_DMA_BUF_EXT, nullptr, attribs);
  if (image == EGL_NO_IMAGE_KHR) {
    g_set_error(error, g_quark_from_static_string("lumit"), 0,
                "eglCreateImageKHR failed for the dma-buf");
    return FALSE;
  }

  GLuint texture = 0;
  glGenTextures(1, &texture);
  glBindTexture(GL_TEXTURE_2D, texture);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  image_target_texture(GL_TEXTURE_2D, image);

  self->egl_image = image;
  self->gl_texture = texture;
  return TRUE;
}

static gboolean lumit_dmabuf_texture_populate(FlTextureGL* texture,
                                              uint32_t* target, uint32_t* name,
                                              uint32_t* width, uint32_t* height,
                                              GError** error) {
  LumitDmabufTexture* self = LUMIT_DMABUF_TEXTURE(texture);
  if (self->failed) {
    g_set_error(error, g_quark_from_static_string("lumit"), 0,
                "dma-buf texture import failed earlier");
    return FALSE;
  }
  if (!self->created) {
    if (!lumit_dmabuf_texture_create(self, error)) {
      self->failed = TRUE;
      return FALSE;
    }
    self->created = TRUE;
  }
  *target = GL_TEXTURE_2D;
  *name = self->gl_texture;
  *width = self->width;
  *height = self->height;
  return TRUE;
}

static void lumit_dmabuf_texture_dispose(GObject* object) {
  LumitDmabufTexture* self = LUMIT_DMABUF_TEXTURE(object);
  // Best-effort teardown. The EGLImage/GL texture are freed when the GL context
  // is torn down; we cannot delete them here without a current context. Closing
  // the fd is always safe and releases the DMA-BUF's descriptor.
  if (self->fd >= 0) {
    close(self->fd);
    self->fd = -1;
  }
  G_OBJECT_CLASS(lumit_dmabuf_texture_parent_class)->dispose(object);
}

static void lumit_dmabuf_texture_class_init(LumitDmabufTextureClass* klass) {
  FL_TEXTURE_GL_CLASS(klass)->populate = lumit_dmabuf_texture_populate;
  G_OBJECT_CLASS(klass)->dispose = lumit_dmabuf_texture_dispose;
}

static void lumit_dmabuf_texture_init(LumitDmabufTexture* self) {
  self->fd = -1;
  self->created = FALSE;
  self->failed = FALSE;
}

static LumitDmabufTexture* lumit_dmabuf_texture_new(int fd, uint32_t width,
                                                    uint32_t height,
                                                    uint32_t stride,
                                                    uint32_t offset,
                                                    uint32_t fourcc,
                                                    uint64_t modifier) {
  LumitDmabufTexture* self = LUMIT_DMABUF_TEXTURE(
      g_object_new(lumit_dmabuf_texture_get_type(), nullptr));
  self->fd = fd;
  self->width = width;
  self->height = height;
  self->stride = stride;
  self->offset = offset;
  self->fourcc = fourcc;
  self->modifier = modifier;
  return self;
}

// ---------------------------------------------------------------------------
// The method-channel bridge state.
// ---------------------------------------------------------------------------

typedef struct {
  FlTextureRegistrar* registrar;  // engine-owned, outlives us
  // texture id (int64) -> FlTexture* (borrowed; the registrar holds the ref).
  GHashTable* textures;
} ViewerTextureBridge;

// Read an integer field from the method-call argument map; returns |fallback|
// when absent or not an int. The standard codec encodes small ints as int32 and
// larger ones as int64, both of which fl_value_get_int handles.
static int64_t GetInt(FlValue* args, const char* key, int64_t fallback) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (v == nullptr || fl_value_get_type(v) != FL_VALUE_TYPE_INT) {
    return fallback;
  }
  return fl_value_get_int(v);
}

static void handle_register(ViewerTextureBridge* bridge, FlValue* args,
                            FlMethodCall* call) {
  int fd = static_cast<int>(GetInt(args, "fd", -1));
  uint32_t width = static_cast<uint32_t>(GetInt(args, "width", 0));
  uint32_t height = static_cast<uint32_t>(GetInt(args, "height", 0));
  uint32_t stride = static_cast<uint32_t>(GetInt(args, "stride", 0));
  uint32_t offset = static_cast<uint32_t>(GetInt(args, "offset", 0));
  uint32_t fourcc = static_cast<uint32_t>(GetInt(args, "fourcc", 0));
  uint64_t modifier = static_cast<uint64_t>(GetInt(args, "modifier", 0));
  if (fd < 0 || width == 0 || height == 0) {
    fl_method_call_respond_error(call, "bad_args",
                                 "register needs fd, width and height", nullptr,
                                 nullptr);
    return;
  }

  LumitDmabufTexture* texture = lumit_dmabuf_texture_new(
      fd, width, height, stride, offset, fourcc, modifier);
  fl_texture_registrar_register_texture(bridge->registrar,
                                        FL_TEXTURE(texture));
  int64_t id = fl_texture_get_id(FL_TEXTURE(texture));
  // The registrar holds the strong ref; keep a borrowed pointer for
  // frameReady/unregister and drop our construction ref.
  g_hash_table_insert(bridge->textures, GINT_TO_POINTER(id), texture);
  g_object_unref(texture);

  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_int(id)));
  fl_method_call_respond(call, response, nullptr);
}

static void handle_frame_ready(ViewerTextureBridge* bridge, FlValue* args,
                               FlMethodCall* call) {
  int64_t id = GetInt(args, "textureId", 0);
  gpointer texture = g_hash_table_lookup(bridge->textures, GINT_TO_POINTER(id));
  if (texture != nullptr) {
    fl_texture_registrar_mark_texture_frame_available(
        bridge->registrar, FL_TEXTURE(texture));
  }
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
  fl_method_call_respond(call, response, nullptr);
}

static void handle_unregister(ViewerTextureBridge* bridge, FlValue* args,
                              FlMethodCall* call) {
  int64_t id = GetInt(args, "textureId", 0);
  gpointer texture = g_hash_table_lookup(bridge->textures, GINT_TO_POINTER(id));
  if (texture != nullptr) {
    fl_texture_registrar_unregister_texture(bridge->registrar,
                                            FL_TEXTURE(texture));
    g_hash_table_remove(bridge->textures, GINT_TO_POINTER(id));
  }
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
  fl_method_call_respond(call, response, nullptr);
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* call,
                           gpointer user_data) {
  ViewerTextureBridge* bridge = static_cast<ViewerTextureBridge*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);

  if (g_strcmp0(method, "register") == 0) {
    handle_register(bridge, args, call);
  } else if (g_strcmp0(method, "frameReady") == 0) {
    handle_frame_ready(bridge, args, call);
  } else if (g_strcmp0(method, "unregister") == 0) {
    handle_unregister(bridge, args, call);
  } else {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(call, response, nullptr);
  }
}

void viewer_texture_bridge_register(FlBinaryMessenger* messenger,
                                    FlTextureRegistrar* registrar) {
  ViewerTextureBridge* bridge = g_new0(ViewerTextureBridge, 1);
  bridge->registrar = registrar;
  bridge->textures = g_hash_table_new(g_direct_hash, g_direct_equal);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  // Leaked deliberately: the channel lives for the whole engine, like the
  // registrar it drives (the app owns a single one per Flutter engine).
  FlMethodChannel* channel = fl_method_channel_new(
      messenger, "lumit/viewer_texture", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, bridge,
                                            nullptr);
}
