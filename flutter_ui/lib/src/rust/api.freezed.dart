// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$LumitProjectItemType {
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is LumitProjectItemType);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'LumitProjectItemType()';
  }
}

/// @nodoc
class $LumitProjectItemTypeCopyWith<$Res> {
  $LumitProjectItemTypeCopyWith(
      LumitProjectItemType _, $Res Function(LumitProjectItemType) __);
}

/// Adds pattern-matching-related methods to [LumitProjectItemType].
extension LumitProjectItemTypePatterns on LumitProjectItemType {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(LumitProjectItemType_Footage value)? footage,
    TResult Function(LumitProjectItemType_Solid value)? solid,
    TResult Function(LumitProjectItemType_Composition value)? composition,
    TResult Function(LumitProjectItemType_Folder value)? folder,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case LumitProjectItemType_Footage() when footage != null:
        return footage(_that);
      case LumitProjectItemType_Solid() when solid != null:
        return solid(_that);
      case LumitProjectItemType_Composition() when composition != null:
        return composition(_that);
      case LumitProjectItemType_Folder() when folder != null:
        return folder(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(LumitProjectItemType_Footage value) footage,
    required TResult Function(LumitProjectItemType_Solid value) solid,
    required TResult Function(LumitProjectItemType_Composition value)
        composition,
    required TResult Function(LumitProjectItemType_Folder value) folder,
  }) {
    final _that = this;
    switch (_that) {
      case LumitProjectItemType_Footage():
        return footage(_that);
      case LumitProjectItemType_Solid():
        return solid(_that);
      case LumitProjectItemType_Composition():
        return composition(_that);
      case LumitProjectItemType_Folder():
        return folder(_that);
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(LumitProjectItemType_Footage value)? footage,
    TResult? Function(LumitProjectItemType_Solid value)? solid,
    TResult? Function(LumitProjectItemType_Composition value)? composition,
    TResult? Function(LumitProjectItemType_Folder value)? folder,
  }) {
    final _that = this;
    switch (_that) {
      case LumitProjectItemType_Footage() when footage != null:
        return footage(_that);
      case LumitProjectItemType_Solid() when solid != null:
        return solid(_that);
      case LumitProjectItemType_Composition() when composition != null:
        return composition(_that);
      case LumitProjectItemType_Folder() when folder != null:
        return folder(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? footage,
    TResult Function()? solid,
    TResult Function(LumitComposition field0)? composition,
    TResult Function()? folder,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case LumitProjectItemType_Footage() when footage != null:
        return footage();
      case LumitProjectItemType_Solid() when solid != null:
        return solid();
      case LumitProjectItemType_Composition() when composition != null:
        return composition(_that.field0);
      case LumitProjectItemType_Folder() when folder != null:
        return folder();
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() footage,
    required TResult Function() solid,
    required TResult Function(LumitComposition field0) composition,
    required TResult Function() folder,
  }) {
    final _that = this;
    switch (_that) {
      case LumitProjectItemType_Footage():
        return footage();
      case LumitProjectItemType_Solid():
        return solid();
      case LumitProjectItemType_Composition():
        return composition(_that.field0);
      case LumitProjectItemType_Folder():
        return folder();
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? footage,
    TResult? Function()? solid,
    TResult? Function(LumitComposition field0)? composition,
    TResult? Function()? folder,
  }) {
    final _that = this;
    switch (_that) {
      case LumitProjectItemType_Footage() when footage != null:
        return footage();
      case LumitProjectItemType_Solid() when solid != null:
        return solid();
      case LumitProjectItemType_Composition() when composition != null:
        return composition(_that.field0);
      case LumitProjectItemType_Folder() when folder != null:
        return folder();
      case _:
        return null;
    }
  }
}

/// @nodoc

class LumitProjectItemType_Footage extends LumitProjectItemType {
  const LumitProjectItemType_Footage() : super._();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is LumitProjectItemType_Footage);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'LumitProjectItemType.footage()';
  }
}

/// @nodoc

class LumitProjectItemType_Solid extends LumitProjectItemType {
  const LumitProjectItemType_Solid() : super._();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is LumitProjectItemType_Solid);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'LumitProjectItemType.solid()';
  }
}

/// @nodoc

class LumitProjectItemType_Composition extends LumitProjectItemType {
  const LumitProjectItemType_Composition(this.field0) : super._();

  final LumitComposition field0;

  /// Create a copy of LumitProjectItemType
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $LumitProjectItemType_CompositionCopyWith<LumitProjectItemType_Composition>
      get copyWith => _$LumitProjectItemType_CompositionCopyWithImpl<
          LumitProjectItemType_Composition>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is LumitProjectItemType_Composition &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  @override
  String toString() {
    return 'LumitProjectItemType.composition(field0: $field0)';
  }
}

/// @nodoc
abstract mixin class $LumitProjectItemType_CompositionCopyWith<$Res>
    implements $LumitProjectItemTypeCopyWith<$Res> {
  factory $LumitProjectItemType_CompositionCopyWith(
          LumitProjectItemType_Composition value,
          $Res Function(LumitProjectItemType_Composition) _then) =
      _$LumitProjectItemType_CompositionCopyWithImpl;
  @useResult
  $Res call({LumitComposition field0});
}

/// @nodoc
class _$LumitProjectItemType_CompositionCopyWithImpl<$Res>
    implements $LumitProjectItemType_CompositionCopyWith<$Res> {
  _$LumitProjectItemType_CompositionCopyWithImpl(this._self, this._then);

  final LumitProjectItemType_Composition _self;
  final $Res Function(LumitProjectItemType_Composition) _then;

  /// Create a copy of LumitProjectItemType
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? field0 = null,
  }) {
    return _then(LumitProjectItemType_Composition(
      null == field0
          ? _self.field0
          : field0 // ignore: cast_nullable_to_non_nullable
              as LumitComposition,
    ));
  }
}

/// @nodoc

class LumitProjectItemType_Folder extends LumitProjectItemType {
  const LumitProjectItemType_Folder() : super._();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is LumitProjectItemType_Folder);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'LumitProjectItemType.folder()';
  }
}

// dart format on
