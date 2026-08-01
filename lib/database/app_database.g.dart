// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class LibraryItems extends Table with TableInfo<LibraryItems, LibraryItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  LibraryItems(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
      'mode', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
      'format', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _libraryStatusMeta =
      const VerificationMeta('libraryStatus');
  late final GeneratedColumn<String> libraryStatus = GeneratedColumn<String>(
      'library_status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  late final GeneratedColumn<double> rating = GeneratedColumn<double>(
      'rating', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _watchedEpisodesMeta =
      const VerificationMeta('watchedEpisodes');
  late final GeneratedColumn<int> watchedEpisodes = GeneratedColumn<int>(
      'watched_episodes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _totalEpisodesMeta =
      const VerificationMeta('totalEpisodes');
  late final GeneratedColumn<int> totalEpisodes = GeneratedColumn<int>(
      'total_episodes', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: '');
  static const VerificationMeta _addedAtMeta =
      const VerificationMeta('addedAt');
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
      'added_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _categoryIdsMeta =
      const VerificationMeta('categoryIds');
  late final GeneratedColumn<String> categoryIds = GeneratedColumn<String>(
      'category_ids', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  @override
  List<GeneratedColumn> get $columns => [
        id,
        mode,
        format,
        libraryStatus,
        rating,
        watchedEpisodes,
        totalEpisodes,
        addedAt,
        categoryIds
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_items';
  @override
  VerificationContext validateIntegrity(Insertable<LibraryItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
          _modeMeta, mode.isAcceptableOrUnknown(data['mode']!, _modeMeta));
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('format')) {
      context.handle(_formatMeta,
          format.isAcceptableOrUnknown(data['format']!, _formatMeta));
    } else if (isInserting) {
      context.missing(_formatMeta);
    }
    if (data.containsKey('library_status')) {
      context.handle(
          _libraryStatusMeta,
          libraryStatus.isAcceptableOrUnknown(
              data['library_status']!, _libraryStatusMeta));
    } else if (isInserting) {
      context.missing(_libraryStatusMeta);
    }
    if (data.containsKey('rating')) {
      context.handle(_ratingMeta,
          rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta));
    } else if (isInserting) {
      context.missing(_ratingMeta);
    }
    if (data.containsKey('watched_episodes')) {
      context.handle(
          _watchedEpisodesMeta,
          watchedEpisodes.isAcceptableOrUnknown(
              data['watched_episodes']!, _watchedEpisodesMeta));
    } else if (isInserting) {
      context.missing(_watchedEpisodesMeta);
    }
    if (data.containsKey('total_episodes')) {
      context.handle(
          _totalEpisodesMeta,
          totalEpisodes.isAcceptableOrUnknown(
              data['total_episodes']!, _totalEpisodesMeta));
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta,
          addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('category_ids')) {
      context.handle(
          _categoryIdsMeta,
          categoryIds.isAcceptableOrUnknown(
              data['category_ids']!, _categoryIdsMeta));
    } else if (isInserting) {
      context.missing(_categoryIdsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, mode};
  @override
  LibraryItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      mode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mode'])!,
      format: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}format'])!,
      libraryStatus: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}library_status'])!,
      rating: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}rating'])!,
      watchedEpisodes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}watched_episodes'])!,
      totalEpisodes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total_episodes']),
      addedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}added_at'])!,
      categoryIds: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category_ids'])!,
    );
  }

  @override
  LibraryItems createAlias(String alias) {
    return LibraryItems(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['PRIMARY KEY(id, mode)'];
  @override
  bool get dontWriteConstraints => true;
}

class LibraryItem extends DataClass implements Insertable<LibraryItem> {
  final int id;
  final String mode;
  final String format;
  final String libraryStatus;
  final double rating;
  final int watchedEpisodes;
  final int? totalEpisodes;
  final DateTime addedAt;
  final String categoryIds;
  const LibraryItem(
      {required this.id,
      required this.mode,
      required this.format,
      required this.libraryStatus,
      required this.rating,
      required this.watchedEpisodes,
      this.totalEpisodes,
      required this.addedAt,
      required this.categoryIds});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['mode'] = Variable<String>(mode);
    map['format'] = Variable<String>(format);
    map['library_status'] = Variable<String>(libraryStatus);
    map['rating'] = Variable<double>(rating);
    map['watched_episodes'] = Variable<int>(watchedEpisodes);
    if (!nullToAbsent || totalEpisodes != null) {
      map['total_episodes'] = Variable<int>(totalEpisodes);
    }
    map['added_at'] = Variable<DateTime>(addedAt);
    map['category_ids'] = Variable<String>(categoryIds);
    return map;
  }

  LibraryItemsCompanion toCompanion(bool nullToAbsent) {
    return LibraryItemsCompanion(
      id: Value(id),
      mode: Value(mode),
      format: Value(format),
      libraryStatus: Value(libraryStatus),
      rating: Value(rating),
      watchedEpisodes: Value(watchedEpisodes),
      totalEpisodes: totalEpisodes == null && nullToAbsent
          ? const Value.absent()
          : Value(totalEpisodes),
      addedAt: Value(addedAt),
      categoryIds: Value(categoryIds),
    );
  }

  factory LibraryItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryItem(
      id: serializer.fromJson<int>(json['id']),
      mode: serializer.fromJson<String>(json['mode']),
      format: serializer.fromJson<String>(json['format']),
      libraryStatus: serializer.fromJson<String>(json['library_status']),
      rating: serializer.fromJson<double>(json['rating']),
      watchedEpisodes: serializer.fromJson<int>(json['watched_episodes']),
      totalEpisodes: serializer.fromJson<int?>(json['total_episodes']),
      addedAt: serializer.fromJson<DateTime>(json['added_at']),
      categoryIds: serializer.fromJson<String>(json['category_ids']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'mode': serializer.toJson<String>(mode),
      'format': serializer.toJson<String>(format),
      'library_status': serializer.toJson<String>(libraryStatus),
      'rating': serializer.toJson<double>(rating),
      'watched_episodes': serializer.toJson<int>(watchedEpisodes),
      'total_episodes': serializer.toJson<int?>(totalEpisodes),
      'added_at': serializer.toJson<DateTime>(addedAt),
      'category_ids': serializer.toJson<String>(categoryIds),
    };
  }

  LibraryItem copyWith(
          {int? id,
          String? mode,
          String? format,
          String? libraryStatus,
          double? rating,
          int? watchedEpisodes,
          Value<int?> totalEpisodes = const Value.absent(),
          DateTime? addedAt,
          String? categoryIds}) =>
      LibraryItem(
        id: id ?? this.id,
        mode: mode ?? this.mode,
        format: format ?? this.format,
        libraryStatus: libraryStatus ?? this.libraryStatus,
        rating: rating ?? this.rating,
        watchedEpisodes: watchedEpisodes ?? this.watchedEpisodes,
        totalEpisodes:
            totalEpisodes.present ? totalEpisodes.value : this.totalEpisodes,
        addedAt: addedAt ?? this.addedAt,
        categoryIds: categoryIds ?? this.categoryIds,
      );
  LibraryItem copyWithCompanion(LibraryItemsCompanion data) {
    return LibraryItem(
      id: data.id.present ? data.id.value : this.id,
      mode: data.mode.present ? data.mode.value : this.mode,
      format: data.format.present ? data.format.value : this.format,
      libraryStatus: data.libraryStatus.present
          ? data.libraryStatus.value
          : this.libraryStatus,
      rating: data.rating.present ? data.rating.value : this.rating,
      watchedEpisodes: data.watchedEpisodes.present
          ? data.watchedEpisodes.value
          : this.watchedEpisodes,
      totalEpisodes: data.totalEpisodes.present
          ? data.totalEpisodes.value
          : this.totalEpisodes,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      categoryIds:
          data.categoryIds.present ? data.categoryIds.value : this.categoryIds,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryItem(')
          ..write('id: $id, ')
          ..write('mode: $mode, ')
          ..write('format: $format, ')
          ..write('libraryStatus: $libraryStatus, ')
          ..write('rating: $rating, ')
          ..write('watchedEpisodes: $watchedEpisodes, ')
          ..write('totalEpisodes: $totalEpisodes, ')
          ..write('addedAt: $addedAt, ')
          ..write('categoryIds: $categoryIds')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, mode, format, libraryStatus, rating,
      watchedEpisodes, totalEpisodes, addedAt, categoryIds);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryItem &&
          other.id == this.id &&
          other.mode == this.mode &&
          other.format == this.format &&
          other.libraryStatus == this.libraryStatus &&
          other.rating == this.rating &&
          other.watchedEpisodes == this.watchedEpisodes &&
          other.totalEpisodes == this.totalEpisodes &&
          other.addedAt == this.addedAt &&
          other.categoryIds == this.categoryIds);
}

class LibraryItemsCompanion extends UpdateCompanion<LibraryItem> {
  final Value<int> id;
  final Value<String> mode;
  final Value<String> format;
  final Value<String> libraryStatus;
  final Value<double> rating;
  final Value<int> watchedEpisodes;
  final Value<int?> totalEpisodes;
  final Value<DateTime> addedAt;
  final Value<String> categoryIds;
  final Value<int> rowid;
  const LibraryItemsCompanion({
    this.id = const Value.absent(),
    this.mode = const Value.absent(),
    this.format = const Value.absent(),
    this.libraryStatus = const Value.absent(),
    this.rating = const Value.absent(),
    this.watchedEpisodes = const Value.absent(),
    this.totalEpisodes = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.categoryIds = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LibraryItemsCompanion.insert({
    required int id,
    required String mode,
    required String format,
    required String libraryStatus,
    required double rating,
    required int watchedEpisodes,
    this.totalEpisodes = const Value.absent(),
    required DateTime addedAt,
    required String categoryIds,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        mode = Value(mode),
        format = Value(format),
        libraryStatus = Value(libraryStatus),
        rating = Value(rating),
        watchedEpisodes = Value(watchedEpisodes),
        addedAt = Value(addedAt),
        categoryIds = Value(categoryIds);
  static Insertable<LibraryItem> custom({
    Expression<int>? id,
    Expression<String>? mode,
    Expression<String>? format,
    Expression<String>? libraryStatus,
    Expression<double>? rating,
    Expression<int>? watchedEpisodes,
    Expression<int>? totalEpisodes,
    Expression<DateTime>? addedAt,
    Expression<String>? categoryIds,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mode != null) 'mode': mode,
      if (format != null) 'format': format,
      if (libraryStatus != null) 'library_status': libraryStatus,
      if (rating != null) 'rating': rating,
      if (watchedEpisodes != null) 'watched_episodes': watchedEpisodes,
      if (totalEpisodes != null) 'total_episodes': totalEpisodes,
      if (addedAt != null) 'added_at': addedAt,
      if (categoryIds != null) 'category_ids': categoryIds,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LibraryItemsCompanion copyWith(
      {Value<int>? id,
      Value<String>? mode,
      Value<String>? format,
      Value<String>? libraryStatus,
      Value<double>? rating,
      Value<int>? watchedEpisodes,
      Value<int?>? totalEpisodes,
      Value<DateTime>? addedAt,
      Value<String>? categoryIds,
      Value<int>? rowid}) {
    return LibraryItemsCompanion(
      id: id ?? this.id,
      mode: mode ?? this.mode,
      format: format ?? this.format,
      libraryStatus: libraryStatus ?? this.libraryStatus,
      rating: rating ?? this.rating,
      watchedEpisodes: watchedEpisodes ?? this.watchedEpisodes,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      addedAt: addedAt ?? this.addedAt,
      categoryIds: categoryIds ?? this.categoryIds,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (libraryStatus.present) {
      map['library_status'] = Variable<String>(libraryStatus.value);
    }
    if (rating.present) {
      map['rating'] = Variable<double>(rating.value);
    }
    if (watchedEpisodes.present) {
      map['watched_episodes'] = Variable<int>(watchedEpisodes.value);
    }
    if (totalEpisodes.present) {
      map['total_episodes'] = Variable<int>(totalEpisodes.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (categoryIds.present) {
      map['category_ids'] = Variable<String>(categoryIds.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibraryItemsCompanion(')
          ..write('id: $id, ')
          ..write('mode: $mode, ')
          ..write('format: $format, ')
          ..write('libraryStatus: $libraryStatus, ')
          ..write('rating: $rating, ')
          ..write('watchedEpisodes: $watchedEpisodes, ')
          ..write('totalEpisodes: $totalEpisodes, ')
          ..write('addedAt: $addedAt, ')
          ..write('categoryIds: $categoryIds, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class LibraryCategories extends Table
    with TableInfo<LibraryCategories, LibraryCategory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  LibraryCategories(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL PRIMARY KEY');
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
      'mode', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  @override
  List<GeneratedColumn> get $columns => [id, name, mode];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_categories';
  @override
  VerificationContext validateIntegrity(Insertable<LibraryCategory> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
          _modeMeta, mode.isAcceptableOrUnknown(data['mode']!, _modeMeta));
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LibraryCategory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryCategory(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      mode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mode'])!,
    );
  }

  @override
  LibraryCategories createAlias(String alias) {
    return LibraryCategories(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class LibraryCategory extends DataClass implements Insertable<LibraryCategory> {
  final String id;
  final String name;
  final String mode;
  const LibraryCategory(
      {required this.id, required this.name, required this.mode});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['mode'] = Variable<String>(mode);
    return map;
  }

  LibraryCategoriesCompanion toCompanion(bool nullToAbsent) {
    return LibraryCategoriesCompanion(
      id: Value(id),
      name: Value(name),
      mode: Value(mode),
    );
  }

  factory LibraryCategory.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryCategory(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      mode: serializer.fromJson<String>(json['mode']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'mode': serializer.toJson<String>(mode),
    };
  }

  LibraryCategory copyWith({String? id, String? name, String? mode}) =>
      LibraryCategory(
        id: id ?? this.id,
        name: name ?? this.name,
        mode: mode ?? this.mode,
      );
  LibraryCategory copyWithCompanion(LibraryCategoriesCompanion data) {
    return LibraryCategory(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      mode: data.mode.present ? data.mode.value : this.mode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryCategory(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('mode: $mode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, mode);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryCategory &&
          other.id == this.id &&
          other.name == this.name &&
          other.mode == this.mode);
}

class LibraryCategoriesCompanion extends UpdateCompanion<LibraryCategory> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> mode;
  final Value<int> rowid;
  const LibraryCategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.mode = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LibraryCategoriesCompanion.insert({
    required String id,
    required String name,
    required String mode,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        mode = Value(mode);
  static Insertable<LibraryCategory> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? mode,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (mode != null) 'mode': mode,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LibraryCategoriesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? mode,
      Value<int>? rowid}) {
    return LibraryCategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      mode: mode ?? this.mode,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibraryCategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('mode: $mode, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class MediaCaches extends Table with TableInfo<MediaCaches, MediaCache> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  MediaCaches(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
      'mode', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _coverImageMeta =
      const VerificationMeta('coverImage');
  late final GeneratedColumn<String> coverImage = GeneratedColumn<String>(
      'cover_image', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _averageScoreMeta =
      const VerificationMeta('averageScore');
  late final GeneratedColumn<int> averageScore = GeneratedColumn<int>(
      'average_score', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: '');
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
      'format', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  static const VerificationMeta _bannerImageMeta =
      const VerificationMeta('bannerImage');
  late final GeneratedColumn<String> bannerImage = GeneratedColumn<String>(
      'banner_image', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  static const VerificationMeta _extraDataMeta =
      const VerificationMeta('extraData');
  late final GeneratedColumn<String> extraData = GeneratedColumn<String>(
      'extra_data', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: '');
  @override
  List<GeneratedColumn> get $columns => [
        id,
        mode,
        title,
        coverImage,
        averageScore,
        format,
        status,
        bannerImage,
        extraData
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_caches';
  @override
  VerificationContext validateIntegrity(Insertable<MediaCache> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
          _modeMeta, mode.isAcceptableOrUnknown(data['mode']!, _modeMeta));
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('cover_image')) {
      context.handle(
          _coverImageMeta,
          coverImage.isAcceptableOrUnknown(
              data['cover_image']!, _coverImageMeta));
    } else if (isInserting) {
      context.missing(_coverImageMeta);
    }
    if (data.containsKey('average_score')) {
      context.handle(
          _averageScoreMeta,
          averageScore.isAcceptableOrUnknown(
              data['average_score']!, _averageScoreMeta));
    }
    if (data.containsKey('format')) {
      context.handle(_formatMeta,
          format.isAcceptableOrUnknown(data['format']!, _formatMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('banner_image')) {
      context.handle(
          _bannerImageMeta,
          bannerImage.isAcceptableOrUnknown(
              data['banner_image']!, _bannerImageMeta));
    }
    if (data.containsKey('extra_data')) {
      context.handle(_extraDataMeta,
          extraData.isAcceptableOrUnknown(data['extra_data']!, _extraDataMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, mode};
  @override
  MediaCache map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaCache(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      mode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mode'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      coverImage: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cover_image'])!,
      averageScore: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}average_score']),
      format: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}format']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status']),
      bannerImage: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}banner_image']),
      extraData: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}extra_data']),
    );
  }

  @override
  MediaCaches createAlias(String alias) {
    return MediaCaches(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints => const ['PRIMARY KEY(id, mode)'];
  @override
  bool get dontWriteConstraints => true;
}

class MediaCache extends DataClass implements Insertable<MediaCache> {
  final int id;
  final String mode;
  final String title;
  final String coverImage;
  final int? averageScore;
  final String? format;
  final String? status;
  final String? bannerImage;
  final String? extraData;
  const MediaCache(
      {required this.id,
      required this.mode,
      required this.title,
      required this.coverImage,
      this.averageScore,
      this.format,
      this.status,
      this.bannerImage,
      this.extraData});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['mode'] = Variable<String>(mode);
    map['title'] = Variable<String>(title);
    map['cover_image'] = Variable<String>(coverImage);
    if (!nullToAbsent || averageScore != null) {
      map['average_score'] = Variable<int>(averageScore);
    }
    if (!nullToAbsent || format != null) {
      map['format'] = Variable<String>(format);
    }
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    if (!nullToAbsent || bannerImage != null) {
      map['banner_image'] = Variable<String>(bannerImage);
    }
    if (!nullToAbsent || extraData != null) {
      map['extra_data'] = Variable<String>(extraData);
    }
    return map;
  }

  MediaCachesCompanion toCompanion(bool nullToAbsent) {
    return MediaCachesCompanion(
      id: Value(id),
      mode: Value(mode),
      title: Value(title),
      coverImage: Value(coverImage),
      averageScore: averageScore == null && nullToAbsent
          ? const Value.absent()
          : Value(averageScore),
      format:
          format == null && nullToAbsent ? const Value.absent() : Value(format),
      status:
          status == null && nullToAbsent ? const Value.absent() : Value(status),
      bannerImage: bannerImage == null && nullToAbsent
          ? const Value.absent()
          : Value(bannerImage),
      extraData: extraData == null && nullToAbsent
          ? const Value.absent()
          : Value(extraData),
    );
  }

  factory MediaCache.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaCache(
      id: serializer.fromJson<int>(json['id']),
      mode: serializer.fromJson<String>(json['mode']),
      title: serializer.fromJson<String>(json['title']),
      coverImage: serializer.fromJson<String>(json['cover_image']),
      averageScore: serializer.fromJson<int?>(json['average_score']),
      format: serializer.fromJson<String?>(json['format']),
      status: serializer.fromJson<String?>(json['status']),
      bannerImage: serializer.fromJson<String?>(json['banner_image']),
      extraData: serializer.fromJson<String?>(json['extra_data']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'mode': serializer.toJson<String>(mode),
      'title': serializer.toJson<String>(title),
      'cover_image': serializer.toJson<String>(coverImage),
      'average_score': serializer.toJson<int?>(averageScore),
      'format': serializer.toJson<String?>(format),
      'status': serializer.toJson<String?>(status),
      'banner_image': serializer.toJson<String?>(bannerImage),
      'extra_data': serializer.toJson<String?>(extraData),
    };
  }

  MediaCache copyWith(
          {int? id,
          String? mode,
          String? title,
          String? coverImage,
          Value<int?> averageScore = const Value.absent(),
          Value<String?> format = const Value.absent(),
          Value<String?> status = const Value.absent(),
          Value<String?> bannerImage = const Value.absent(),
          Value<String?> extraData = const Value.absent()}) =>
      MediaCache(
        id: id ?? this.id,
        mode: mode ?? this.mode,
        title: title ?? this.title,
        coverImage: coverImage ?? this.coverImage,
        averageScore:
            averageScore.present ? averageScore.value : this.averageScore,
        format: format.present ? format.value : this.format,
        status: status.present ? status.value : this.status,
        bannerImage: bannerImage.present ? bannerImage.value : this.bannerImage,
        extraData: extraData.present ? extraData.value : this.extraData,
      );
  MediaCache copyWithCompanion(MediaCachesCompanion data) {
    return MediaCache(
      id: data.id.present ? data.id.value : this.id,
      mode: data.mode.present ? data.mode.value : this.mode,
      title: data.title.present ? data.title.value : this.title,
      coverImage:
          data.coverImage.present ? data.coverImage.value : this.coverImage,
      averageScore: data.averageScore.present
          ? data.averageScore.value
          : this.averageScore,
      format: data.format.present ? data.format.value : this.format,
      status: data.status.present ? data.status.value : this.status,
      bannerImage:
          data.bannerImage.present ? data.bannerImage.value : this.bannerImage,
      extraData: data.extraData.present ? data.extraData.value : this.extraData,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaCache(')
          ..write('id: $id, ')
          ..write('mode: $mode, ')
          ..write('title: $title, ')
          ..write('coverImage: $coverImage, ')
          ..write('averageScore: $averageScore, ')
          ..write('format: $format, ')
          ..write('status: $status, ')
          ..write('bannerImage: $bannerImage, ')
          ..write('extraData: $extraData')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, mode, title, coverImage, averageScore,
      format, status, bannerImage, extraData);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaCache &&
          other.id == this.id &&
          other.mode == this.mode &&
          other.title == this.title &&
          other.coverImage == this.coverImage &&
          other.averageScore == this.averageScore &&
          other.format == this.format &&
          other.status == this.status &&
          other.bannerImage == this.bannerImage &&
          other.extraData == this.extraData);
}

class MediaCachesCompanion extends UpdateCompanion<MediaCache> {
  final Value<int> id;
  final Value<String> mode;
  final Value<String> title;
  final Value<String> coverImage;
  final Value<int?> averageScore;
  final Value<String?> format;
  final Value<String?> status;
  final Value<String?> bannerImage;
  final Value<String?> extraData;
  final Value<int> rowid;
  const MediaCachesCompanion({
    this.id = const Value.absent(),
    this.mode = const Value.absent(),
    this.title = const Value.absent(),
    this.coverImage = const Value.absent(),
    this.averageScore = const Value.absent(),
    this.format = const Value.absent(),
    this.status = const Value.absent(),
    this.bannerImage = const Value.absent(),
    this.extraData = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaCachesCompanion.insert({
    required int id,
    required String mode,
    required String title,
    required String coverImage,
    this.averageScore = const Value.absent(),
    this.format = const Value.absent(),
    this.status = const Value.absent(),
    this.bannerImage = const Value.absent(),
    this.extraData = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        mode = Value(mode),
        title = Value(title),
        coverImage = Value(coverImage);
  static Insertable<MediaCache> custom({
    Expression<int>? id,
    Expression<String>? mode,
    Expression<String>? title,
    Expression<String>? coverImage,
    Expression<int>? averageScore,
    Expression<String>? format,
    Expression<String>? status,
    Expression<String>? bannerImage,
    Expression<String>? extraData,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mode != null) 'mode': mode,
      if (title != null) 'title': title,
      if (coverImage != null) 'cover_image': coverImage,
      if (averageScore != null) 'average_score': averageScore,
      if (format != null) 'format': format,
      if (status != null) 'status': status,
      if (bannerImage != null) 'banner_image': bannerImage,
      if (extraData != null) 'extra_data': extraData,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaCachesCompanion copyWith(
      {Value<int>? id,
      Value<String>? mode,
      Value<String>? title,
      Value<String>? coverImage,
      Value<int?>? averageScore,
      Value<String?>? format,
      Value<String?>? status,
      Value<String?>? bannerImage,
      Value<String?>? extraData,
      Value<int>? rowid}) {
    return MediaCachesCompanion(
      id: id ?? this.id,
      mode: mode ?? this.mode,
      title: title ?? this.title,
      coverImage: coverImage ?? this.coverImage,
      averageScore: averageScore ?? this.averageScore,
      format: format ?? this.format,
      status: status ?? this.status,
      bannerImage: bannerImage ?? this.bannerImage,
      extraData: extraData ?? this.extraData,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (coverImage.present) {
      map['cover_image'] = Variable<String>(coverImage.value);
    }
    if (averageScore.present) {
      map['average_score'] = Variable<int>(averageScore.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (bannerImage.present) {
      map['banner_image'] = Variable<String>(bannerImage.value);
    }
    if (extraData.present) {
      map['extra_data'] = Variable<String>(extraData.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaCachesCompanion(')
          ..write('id: $id, ')
          ..write('mode: $mode, ')
          ..write('title: $title, ')
          ..write('coverImage: $coverImage, ')
          ..write('averageScore: $averageScore, ')
          ..write('format: $format, ')
          ..write('status: $status, ')
          ..write('bannerImage: $bannerImage, ')
          ..write('extraData: $extraData, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class NotificationAcks extends Table
    with TableInfo<NotificationAcks, NotificationAck> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  NotificationAcks(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaKeyMeta =
      const VerificationMeta('mediaKey');
  late final GeneratedColumn<String> mediaKey = GeneratedColumn<String>(
      'media_key', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL PRIMARY KEY');
  static const VerificationMeta _ackValueMeta =
      const VerificationMeta('ackValue');
  late final GeneratedColumn<int> ackValue = GeneratedColumn<int>(
      'ack_value', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _startValueMeta =
      const VerificationMeta('startValue');
  late final GeneratedColumn<int> startValue = GeneratedColumn<int>(
      'start_value', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  @override
  List<GeneratedColumn> get $columns => [mediaKey, ackValue, startValue];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notification_acks';
  @override
  VerificationContext validateIntegrity(Insertable<NotificationAck> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_key')) {
      context.handle(_mediaKeyMeta,
          mediaKey.isAcceptableOrUnknown(data['media_key']!, _mediaKeyMeta));
    } else if (isInserting) {
      context.missing(_mediaKeyMeta);
    }
    if (data.containsKey('ack_value')) {
      context.handle(_ackValueMeta,
          ackValue.isAcceptableOrUnknown(data['ack_value']!, _ackValueMeta));
    } else if (isInserting) {
      context.missing(_ackValueMeta);
    }
    if (data.containsKey('start_value')) {
      context.handle(
          _startValueMeta,
          startValue.isAcceptableOrUnknown(
              data['start_value']!, _startValueMeta));
    } else if (isInserting) {
      context.missing(_startValueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mediaKey};
  @override
  NotificationAck map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NotificationAck(
      mediaKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}media_key'])!,
      ackValue: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ack_value'])!,
      startValue: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}start_value'])!,
    );
  }

  @override
  NotificationAcks createAlias(String alias) {
    return NotificationAcks(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class NotificationAck extends DataClass implements Insertable<NotificationAck> {
  final String mediaKey;

  /// Format: 'mode_id' (e.g. 'anime_123')
  final int ackValue;
  final int startValue;
  const NotificationAck(
      {required this.mediaKey,
      required this.ackValue,
      required this.startValue});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_key'] = Variable<String>(mediaKey);
    map['ack_value'] = Variable<int>(ackValue);
    map['start_value'] = Variable<int>(startValue);
    return map;
  }

  NotificationAcksCompanion toCompanion(bool nullToAbsent) {
    return NotificationAcksCompanion(
      mediaKey: Value(mediaKey),
      ackValue: Value(ackValue),
      startValue: Value(startValue),
    );
  }

  factory NotificationAck.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NotificationAck(
      mediaKey: serializer.fromJson<String>(json['media_key']),
      ackValue: serializer.fromJson<int>(json['ack_value']),
      startValue: serializer.fromJson<int>(json['start_value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'media_key': serializer.toJson<String>(mediaKey),
      'ack_value': serializer.toJson<int>(ackValue),
      'start_value': serializer.toJson<int>(startValue),
    };
  }

  NotificationAck copyWith(
          {String? mediaKey, int? ackValue, int? startValue}) =>
      NotificationAck(
        mediaKey: mediaKey ?? this.mediaKey,
        ackValue: ackValue ?? this.ackValue,
        startValue: startValue ?? this.startValue,
      );
  NotificationAck copyWithCompanion(NotificationAcksCompanion data) {
    return NotificationAck(
      mediaKey: data.mediaKey.present ? data.mediaKey.value : this.mediaKey,
      ackValue: data.ackValue.present ? data.ackValue.value : this.ackValue,
      startValue:
          data.startValue.present ? data.startValue.value : this.startValue,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NotificationAck(')
          ..write('mediaKey: $mediaKey, ')
          ..write('ackValue: $ackValue, ')
          ..write('startValue: $startValue')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mediaKey, ackValue, startValue);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NotificationAck &&
          other.mediaKey == this.mediaKey &&
          other.ackValue == this.ackValue &&
          other.startValue == this.startValue);
}

class NotificationAcksCompanion extends UpdateCompanion<NotificationAck> {
  final Value<String> mediaKey;
  final Value<int> ackValue;
  final Value<int> startValue;
  final Value<int> rowid;
  const NotificationAcksCompanion({
    this.mediaKey = const Value.absent(),
    this.ackValue = const Value.absent(),
    this.startValue = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotificationAcksCompanion.insert({
    required String mediaKey,
    required int ackValue,
    required int startValue,
    this.rowid = const Value.absent(),
  })  : mediaKey = Value(mediaKey),
        ackValue = Value(ackValue),
        startValue = Value(startValue);
  static Insertable<NotificationAck> custom({
    Expression<String>? mediaKey,
    Expression<int>? ackValue,
    Expression<int>? startValue,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaKey != null) 'media_key': mediaKey,
      if (ackValue != null) 'ack_value': ackValue,
      if (startValue != null) 'start_value': startValue,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotificationAcksCompanion copyWith(
      {Value<String>? mediaKey,
      Value<int>? ackValue,
      Value<int>? startValue,
      Value<int>? rowid}) {
    return NotificationAcksCompanion(
      mediaKey: mediaKey ?? this.mediaKey,
      ackValue: ackValue ?? this.ackValue,
      startValue: startValue ?? this.startValue,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaKey.present) {
      map['media_key'] = Variable<String>(mediaKey.value);
    }
    if (ackValue.present) {
      map['ack_value'] = Variable<int>(ackValue.value);
    }
    if (startValue.present) {
      map['start_value'] = Variable<int>(startValue.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotificationAcksCompanion(')
          ..write('mediaKey: $mediaKey, ')
          ..write('ackValue: $ackValue, ')
          ..write('startValue: $startValue, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class WatchHistory extends Table
    with TableInfo<WatchHistory, WatchHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  WatchHistory(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaIdMeta =
      const VerificationMeta('mediaId');
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
      'media_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _isAnimeMeta =
      const VerificationMeta('isAnime');
  late final GeneratedColumn<int> isAnime = GeneratedColumn<int>(
      'is_anime', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _isMangaMeta =
      const VerificationMeta('isManga');
  late final GeneratedColumn<int> isManga = GeneratedColumn<int>(
      'is_manga', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _coverImageMeta =
      const VerificationMeta('coverImage');
  late final GeneratedColumn<String> coverImage = GeneratedColumn<String>(
      'cover_image', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
      'format', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _averageScoreMeta =
      const VerificationMeta('averageScore');
  late final GeneratedColumn<double> averageScore = GeneratedColumn<double>(
      'average_score', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT 0.0',
      defaultValue: const CustomExpression('0.0'));
  static const VerificationMeta _totalEpisodesMeta =
      const VerificationMeta('totalEpisodes');
  late final GeneratedColumn<int> totalEpisodes = GeneratedColumn<int>(
      'total_episodes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT 0',
      defaultValue: const CustomExpression('0'));
  static const VerificationMeta _mediaTypeHintMeta =
      const VerificationMeta('mediaTypeHint');
  late final GeneratedColumn<String> mediaTypeHint = GeneratedColumn<String>(
      'media_type_hint', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      $customConstraints: 'NOT NULL DEFAULT \'\'',
      defaultValue: const CustomExpression('\'\''));
  static const VerificationMeta _episodesMeta =
      const VerificationMeta('episodes');
  late final GeneratedColumn<String> episodes = GeneratedColumn<String>(
      'episodes', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _timestampMeta =
      const VerificationMeta('timestamp');
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
      'timestamp', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  @override
  List<GeneratedColumn> get $columns => [
        mediaId,
        isAnime,
        isManga,
        title,
        coverImage,
        format,
        averageScore,
        totalEpisodes,
        mediaTypeHint,
        episodes,
        timestamp
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watch_history';
  @override
  VerificationContext validateIntegrity(Insertable<WatchHistoryData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_id')) {
      context.handle(_mediaIdMeta,
          mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta));
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('is_anime')) {
      context.handle(_isAnimeMeta,
          isAnime.isAcceptableOrUnknown(data['is_anime']!, _isAnimeMeta));
    } else if (isInserting) {
      context.missing(_isAnimeMeta);
    }
    if (data.containsKey('is_manga')) {
      context.handle(_isMangaMeta,
          isManga.isAcceptableOrUnknown(data['is_manga']!, _isMangaMeta));
    } else if (isInserting) {
      context.missing(_isMangaMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('cover_image')) {
      context.handle(
          _coverImageMeta,
          coverImage.isAcceptableOrUnknown(
              data['cover_image']!, _coverImageMeta));
    } else if (isInserting) {
      context.missing(_coverImageMeta);
    }
    if (data.containsKey('format')) {
      context.handle(_formatMeta,
          format.isAcceptableOrUnknown(data['format']!, _formatMeta));
    } else if (isInserting) {
      context.missing(_formatMeta);
    }
    if (data.containsKey('average_score')) {
      context.handle(
          _averageScoreMeta,
          averageScore.isAcceptableOrUnknown(
              data['average_score']!, _averageScoreMeta));
    }
    if (data.containsKey('total_episodes')) {
      context.handle(
          _totalEpisodesMeta,
          totalEpisodes.isAcceptableOrUnknown(
              data['total_episodes']!, _totalEpisodesMeta));
    }
    if (data.containsKey('media_type_hint')) {
      context.handle(
          _mediaTypeHintMeta,
          mediaTypeHint.isAcceptableOrUnknown(
              data['media_type_hint']!, _mediaTypeHintMeta));
    }
    if (data.containsKey('episodes')) {
      context.handle(_episodesMeta,
          episodes.isAcceptableOrUnknown(data['episodes']!, _episodesMeta));
    } else if (isInserting) {
      context.missing(_episodesMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(_timestampMeta,
          timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mediaId, isManga};
  @override
  WatchHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchHistoryData(
      mediaId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}media_id'])!,
      isAnime: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}is_anime'])!,
      isManga: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}is_manga'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      coverImage: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cover_image'])!,
      format: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}format'])!,
      averageScore: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}average_score'])!,
      totalEpisodes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total_episodes'])!,
      mediaTypeHint: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}media_type_hint'])!,
      episodes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}episodes'])!,
      timestamp: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}timestamp'])!,
    );
  }

  @override
  WatchHistory createAlias(String alias) {
    return WatchHistory(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints =>
      const ['PRIMARY KEY(media_id, is_manga)'];
  @override
  bool get dontWriteConstraints => true;
}

class WatchHistoryData extends DataClass
    implements Insertable<WatchHistoryData> {
  final String mediaId;
  final int isAnime;

  /// 0 or 1
  final int isManga;

  /// 0 or 1
  final String title;
  final String coverImage;
  final String format;
  final double averageScore;
  final int totalEpisodes;
  final String mediaTypeHint;
  final String episodes;

  /// JSON list of watched numbers e.g. [1, 2, 3]
  final int timestamp;
  const WatchHistoryData(
      {required this.mediaId,
      required this.isAnime,
      required this.isManga,
      required this.title,
      required this.coverImage,
      required this.format,
      required this.averageScore,
      required this.totalEpisodes,
      required this.mediaTypeHint,
      required this.episodes,
      required this.timestamp});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_id'] = Variable<String>(mediaId);
    map['is_anime'] = Variable<int>(isAnime);
    map['is_manga'] = Variable<int>(isManga);
    map['title'] = Variable<String>(title);
    map['cover_image'] = Variable<String>(coverImage);
    map['format'] = Variable<String>(format);
    map['average_score'] = Variable<double>(averageScore);
    map['total_episodes'] = Variable<int>(totalEpisodes);
    map['media_type_hint'] = Variable<String>(mediaTypeHint);
    map['episodes'] = Variable<String>(episodes);
    map['timestamp'] = Variable<int>(timestamp);
    return map;
  }

  WatchHistoryCompanion toCompanion(bool nullToAbsent) {
    return WatchHistoryCompanion(
      mediaId: Value(mediaId),
      isAnime: Value(isAnime),
      isManga: Value(isManga),
      title: Value(title),
      coverImage: Value(coverImage),
      format: Value(format),
      averageScore: Value(averageScore),
      totalEpisodes: Value(totalEpisodes),
      mediaTypeHint: Value(mediaTypeHint),
      episodes: Value(episodes),
      timestamp: Value(timestamp),
    );
  }

  factory WatchHistoryData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchHistoryData(
      mediaId: serializer.fromJson<String>(json['media_id']),
      isAnime: serializer.fromJson<int>(json['is_anime']),
      isManga: serializer.fromJson<int>(json['is_manga']),
      title: serializer.fromJson<String>(json['title']),
      coverImage: serializer.fromJson<String>(json['cover_image']),
      format: serializer.fromJson<String>(json['format']),
      averageScore: serializer.fromJson<double>(json['average_score']),
      totalEpisodes: serializer.fromJson<int>(json['total_episodes']),
      mediaTypeHint: serializer.fromJson<String>(json['media_type_hint']),
      episodes: serializer.fromJson<String>(json['episodes']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'media_id': serializer.toJson<String>(mediaId),
      'is_anime': serializer.toJson<int>(isAnime),
      'is_manga': serializer.toJson<int>(isManga),
      'title': serializer.toJson<String>(title),
      'cover_image': serializer.toJson<String>(coverImage),
      'format': serializer.toJson<String>(format),
      'average_score': serializer.toJson<double>(averageScore),
      'total_episodes': serializer.toJson<int>(totalEpisodes),
      'media_type_hint': serializer.toJson<String>(mediaTypeHint),
      'episodes': serializer.toJson<String>(episodes),
      'timestamp': serializer.toJson<int>(timestamp),
    };
  }

  WatchHistoryData copyWith(
          {String? mediaId,
          int? isAnime,
          int? isManga,
          String? title,
          String? coverImage,
          String? format,
          double? averageScore,
          int? totalEpisodes,
          String? mediaTypeHint,
          String? episodes,
          int? timestamp}) =>
      WatchHistoryData(
        mediaId: mediaId ?? this.mediaId,
        isAnime: isAnime ?? this.isAnime,
        isManga: isManga ?? this.isManga,
        title: title ?? this.title,
        coverImage: coverImage ?? this.coverImage,
        format: format ?? this.format,
        averageScore: averageScore ?? this.averageScore,
        totalEpisodes: totalEpisodes ?? this.totalEpisodes,
        mediaTypeHint: mediaTypeHint ?? this.mediaTypeHint,
        episodes: episodes ?? this.episodes,
        timestamp: timestamp ?? this.timestamp,
      );
  WatchHistoryData copyWithCompanion(WatchHistoryCompanion data) {
    return WatchHistoryData(
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      isAnime: data.isAnime.present ? data.isAnime.value : this.isAnime,
      isManga: data.isManga.present ? data.isManga.value : this.isManga,
      title: data.title.present ? data.title.value : this.title,
      coverImage:
          data.coverImage.present ? data.coverImage.value : this.coverImage,
      format: data.format.present ? data.format.value : this.format,
      averageScore: data.averageScore.present
          ? data.averageScore.value
          : this.averageScore,
      totalEpisodes: data.totalEpisodes.present
          ? data.totalEpisodes.value
          : this.totalEpisodes,
      mediaTypeHint: data.mediaTypeHint.present
          ? data.mediaTypeHint.value
          : this.mediaTypeHint,
      episodes: data.episodes.present ? data.episodes.value : this.episodes,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchHistoryData(')
          ..write('mediaId: $mediaId, ')
          ..write('isAnime: $isAnime, ')
          ..write('isManga: $isManga, ')
          ..write('title: $title, ')
          ..write('coverImage: $coverImage, ')
          ..write('format: $format, ')
          ..write('averageScore: $averageScore, ')
          ..write('totalEpisodes: $totalEpisodes, ')
          ..write('mediaTypeHint: $mediaTypeHint, ')
          ..write('episodes: $episodes, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mediaId, isAnime, isManga, title, coverImage,
      format, averageScore, totalEpisodes, mediaTypeHint, episodes, timestamp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchHistoryData &&
          other.mediaId == this.mediaId &&
          other.isAnime == this.isAnime &&
          other.isManga == this.isManga &&
          other.title == this.title &&
          other.coverImage == this.coverImage &&
          other.format == this.format &&
          other.averageScore == this.averageScore &&
          other.totalEpisodes == this.totalEpisodes &&
          other.mediaTypeHint == this.mediaTypeHint &&
          other.episodes == this.episodes &&
          other.timestamp == this.timestamp);
}

class WatchHistoryCompanion extends UpdateCompanion<WatchHistoryData> {
  final Value<String> mediaId;
  final Value<int> isAnime;
  final Value<int> isManga;
  final Value<String> title;
  final Value<String> coverImage;
  final Value<String> format;
  final Value<double> averageScore;
  final Value<int> totalEpisodes;
  final Value<String> mediaTypeHint;
  final Value<String> episodes;
  final Value<int> timestamp;
  final Value<int> rowid;
  const WatchHistoryCompanion({
    this.mediaId = const Value.absent(),
    this.isAnime = const Value.absent(),
    this.isManga = const Value.absent(),
    this.title = const Value.absent(),
    this.coverImage = const Value.absent(),
    this.format = const Value.absent(),
    this.averageScore = const Value.absent(),
    this.totalEpisodes = const Value.absent(),
    this.mediaTypeHint = const Value.absent(),
    this.episodes = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WatchHistoryCompanion.insert({
    required String mediaId,
    required int isAnime,
    required int isManga,
    required String title,
    required String coverImage,
    required String format,
    this.averageScore = const Value.absent(),
    this.totalEpisodes = const Value.absent(),
    this.mediaTypeHint = const Value.absent(),
    required String episodes,
    required int timestamp,
    this.rowid = const Value.absent(),
  })  : mediaId = Value(mediaId),
        isAnime = Value(isAnime),
        isManga = Value(isManga),
        title = Value(title),
        coverImage = Value(coverImage),
        format = Value(format),
        episodes = Value(episodes),
        timestamp = Value(timestamp);
  static Insertable<WatchHistoryData> custom({
    Expression<String>? mediaId,
    Expression<int>? isAnime,
    Expression<int>? isManga,
    Expression<String>? title,
    Expression<String>? coverImage,
    Expression<String>? format,
    Expression<double>? averageScore,
    Expression<int>? totalEpisodes,
    Expression<String>? mediaTypeHint,
    Expression<String>? episodes,
    Expression<int>? timestamp,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaId != null) 'media_id': mediaId,
      if (isAnime != null) 'is_anime': isAnime,
      if (isManga != null) 'is_manga': isManga,
      if (title != null) 'title': title,
      if (coverImage != null) 'cover_image': coverImage,
      if (format != null) 'format': format,
      if (averageScore != null) 'average_score': averageScore,
      if (totalEpisodes != null) 'total_episodes': totalEpisodes,
      if (mediaTypeHint != null) 'media_type_hint': mediaTypeHint,
      if (episodes != null) 'episodes': episodes,
      if (timestamp != null) 'timestamp': timestamp,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WatchHistoryCompanion copyWith(
      {Value<String>? mediaId,
      Value<int>? isAnime,
      Value<int>? isManga,
      Value<String>? title,
      Value<String>? coverImage,
      Value<String>? format,
      Value<double>? averageScore,
      Value<int>? totalEpisodes,
      Value<String>? mediaTypeHint,
      Value<String>? episodes,
      Value<int>? timestamp,
      Value<int>? rowid}) {
    return WatchHistoryCompanion(
      mediaId: mediaId ?? this.mediaId,
      isAnime: isAnime ?? this.isAnime,
      isManga: isManga ?? this.isManga,
      title: title ?? this.title,
      coverImage: coverImage ?? this.coverImage,
      format: format ?? this.format,
      averageScore: averageScore ?? this.averageScore,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      mediaTypeHint: mediaTypeHint ?? this.mediaTypeHint,
      episodes: episodes ?? this.episodes,
      timestamp: timestamp ?? this.timestamp,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (isAnime.present) {
      map['is_anime'] = Variable<int>(isAnime.value);
    }
    if (isManga.present) {
      map['is_manga'] = Variable<int>(isManga.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (coverImage.present) {
      map['cover_image'] = Variable<String>(coverImage.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (averageScore.present) {
      map['average_score'] = Variable<double>(averageScore.value);
    }
    if (totalEpisodes.present) {
      map['total_episodes'] = Variable<int>(totalEpisodes.value);
    }
    if (mediaTypeHint.present) {
      map['media_type_hint'] = Variable<String>(mediaTypeHint.value);
    }
    if (episodes.present) {
      map['episodes'] = Variable<String>(episodes.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchHistoryCompanion(')
          ..write('mediaId: $mediaId, ')
          ..write('isAnime: $isAnime, ')
          ..write('isManga: $isManga, ')
          ..write('title: $title, ')
          ..write('coverImage: $coverImage, ')
          ..write('format: $format, ')
          ..write('averageScore: $averageScore, ')
          ..write('totalEpisodes: $totalEpisodes, ')
          ..write('mediaTypeHint: $mediaTypeHint, ')
          ..write('episodes: $episodes, ')
          ..write('timestamp: $timestamp, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class ContinueWatching extends Table
    with TableInfo<ContinueWatching, ContinueWatchingData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  ContinueWatching(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaIdMeta =
      const VerificationMeta('mediaId');
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
      'media_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL PRIMARY KEY');
  static const VerificationMeta _prefixMeta = const VerificationMeta('prefix');
  late final GeneratedColumn<String> prefix = GeneratedColumn<String>(
      'prefix', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _metadataJsonMeta =
      const VerificationMeta('metadataJson');
  late final GeneratedColumn<String> metadataJson = GeneratedColumn<String>(
      'metadata_json', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _lastEpisodeMeta =
      const VerificationMeta('lastEpisode');
  late final GeneratedColumn<int> lastEpisode = GeneratedColumn<int>(
      'last_episode', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _timestampMeta =
      const VerificationMeta('timestamp');
  late final GeneratedColumn<int> timestamp = GeneratedColumn<int>(
      'timestamp', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  @override
  List<GeneratedColumn> get $columns =>
      [mediaId, prefix, metadataJson, lastEpisode, timestamp];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'continue_watching';
  @override
  VerificationContext validateIntegrity(
      Insertable<ContinueWatchingData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_id')) {
      context.handle(_mediaIdMeta,
          mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta));
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('prefix')) {
      context.handle(_prefixMeta,
          prefix.isAcceptableOrUnknown(data['prefix']!, _prefixMeta));
    } else if (isInserting) {
      context.missing(_prefixMeta);
    }
    if (data.containsKey('metadata_json')) {
      context.handle(
          _metadataJsonMeta,
          metadataJson.isAcceptableOrUnknown(
              data['metadata_json']!, _metadataJsonMeta));
    } else if (isInserting) {
      context.missing(_metadataJsonMeta);
    }
    if (data.containsKey('last_episode')) {
      context.handle(
          _lastEpisodeMeta,
          lastEpisode.isAcceptableOrUnknown(
              data['last_episode']!, _lastEpisodeMeta));
    } else if (isInserting) {
      context.missing(_lastEpisodeMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(_timestampMeta,
          timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mediaId};
  @override
  ContinueWatchingData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContinueWatchingData(
      mediaId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}media_id'])!,
      prefix: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}prefix'])!,
      metadataJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}metadata_json'])!,
      lastEpisode: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_episode'])!,
      timestamp: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}timestamp'])!,
    );
  }

  @override
  ContinueWatching createAlias(String alias) {
    return ContinueWatching(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
}

class ContinueWatchingData extends DataClass
    implements Insertable<ContinueWatchingData> {
  final String mediaId;
  final String prefix;

  /// 'anime_' or 'movie_'
  final String metadataJson;
  final int lastEpisode;
  final int timestamp;
  const ContinueWatchingData(
      {required this.mediaId,
      required this.prefix,
      required this.metadataJson,
      required this.lastEpisode,
      required this.timestamp});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_id'] = Variable<String>(mediaId);
    map['prefix'] = Variable<String>(prefix);
    map['metadata_json'] = Variable<String>(metadataJson);
    map['last_episode'] = Variable<int>(lastEpisode);
    map['timestamp'] = Variable<int>(timestamp);
    return map;
  }

  ContinueWatchingCompanion toCompanion(bool nullToAbsent) {
    return ContinueWatchingCompanion(
      mediaId: Value(mediaId),
      prefix: Value(prefix),
      metadataJson: Value(metadataJson),
      lastEpisode: Value(lastEpisode),
      timestamp: Value(timestamp),
    );
  }

  factory ContinueWatchingData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContinueWatchingData(
      mediaId: serializer.fromJson<String>(json['media_id']),
      prefix: serializer.fromJson<String>(json['prefix']),
      metadataJson: serializer.fromJson<String>(json['metadata_json']),
      lastEpisode: serializer.fromJson<int>(json['last_episode']),
      timestamp: serializer.fromJson<int>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'media_id': serializer.toJson<String>(mediaId),
      'prefix': serializer.toJson<String>(prefix),
      'metadata_json': serializer.toJson<String>(metadataJson),
      'last_episode': serializer.toJson<int>(lastEpisode),
      'timestamp': serializer.toJson<int>(timestamp),
    };
  }

  ContinueWatchingData copyWith(
          {String? mediaId,
          String? prefix,
          String? metadataJson,
          int? lastEpisode,
          int? timestamp}) =>
      ContinueWatchingData(
        mediaId: mediaId ?? this.mediaId,
        prefix: prefix ?? this.prefix,
        metadataJson: metadataJson ?? this.metadataJson,
        lastEpisode: lastEpisode ?? this.lastEpisode,
        timestamp: timestamp ?? this.timestamp,
      );
  ContinueWatchingData copyWithCompanion(ContinueWatchingCompanion data) {
    return ContinueWatchingData(
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      prefix: data.prefix.present ? data.prefix.value : this.prefix,
      metadataJson: data.metadataJson.present
          ? data.metadataJson.value
          : this.metadataJson,
      lastEpisode:
          data.lastEpisode.present ? data.lastEpisode.value : this.lastEpisode,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContinueWatchingData(')
          ..write('mediaId: $mediaId, ')
          ..write('prefix: $prefix, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('lastEpisode: $lastEpisode, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(mediaId, prefix, metadataJson, lastEpisode, timestamp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContinueWatchingData &&
          other.mediaId == this.mediaId &&
          other.prefix == this.prefix &&
          other.metadataJson == this.metadataJson &&
          other.lastEpisode == this.lastEpisode &&
          other.timestamp == this.timestamp);
}

class ContinueWatchingCompanion extends UpdateCompanion<ContinueWatchingData> {
  final Value<String> mediaId;
  final Value<String> prefix;
  final Value<String> metadataJson;
  final Value<int> lastEpisode;
  final Value<int> timestamp;
  final Value<int> rowid;
  const ContinueWatchingCompanion({
    this.mediaId = const Value.absent(),
    this.prefix = const Value.absent(),
    this.metadataJson = const Value.absent(),
    this.lastEpisode = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ContinueWatchingCompanion.insert({
    required String mediaId,
    required String prefix,
    required String metadataJson,
    required int lastEpisode,
    required int timestamp,
    this.rowid = const Value.absent(),
  })  : mediaId = Value(mediaId),
        prefix = Value(prefix),
        metadataJson = Value(metadataJson),
        lastEpisode = Value(lastEpisode),
        timestamp = Value(timestamp);
  static Insertable<ContinueWatchingData> custom({
    Expression<String>? mediaId,
    Expression<String>? prefix,
    Expression<String>? metadataJson,
    Expression<int>? lastEpisode,
    Expression<int>? timestamp,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaId != null) 'media_id': mediaId,
      if (prefix != null) 'prefix': prefix,
      if (metadataJson != null) 'metadata_json': metadataJson,
      if (lastEpisode != null) 'last_episode': lastEpisode,
      if (timestamp != null) 'timestamp': timestamp,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ContinueWatchingCompanion copyWith(
      {Value<String>? mediaId,
      Value<String>? prefix,
      Value<String>? metadataJson,
      Value<int>? lastEpisode,
      Value<int>? timestamp,
      Value<int>? rowid}) {
    return ContinueWatchingCompanion(
      mediaId: mediaId ?? this.mediaId,
      prefix: prefix ?? this.prefix,
      metadataJson: metadataJson ?? this.metadataJson,
      lastEpisode: lastEpisode ?? this.lastEpisode,
      timestamp: timestamp ?? this.timestamp,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (prefix.present) {
      map['prefix'] = Variable<String>(prefix.value);
    }
    if (metadataJson.present) {
      map['metadata_json'] = Variable<String>(metadataJson.value);
    }
    if (lastEpisode.present) {
      map['last_episode'] = Variable<int>(lastEpisode.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<int>(timestamp.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContinueWatchingCompanion(')
          ..write('mediaId: $mediaId, ')
          ..write('prefix: $prefix, ')
          ..write('metadataJson: $metadataJson, ')
          ..write('lastEpisode: $lastEpisode, ')
          ..write('timestamp: $timestamp, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class PlaybackPositions extends Table
    with TableInfo<PlaybackPositions, PlaybackPosition> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  PlaybackPositions(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaIdMeta =
      const VerificationMeta('mediaId');
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
      'media_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _episodeMeta =
      const VerificationMeta('episode');
  late final GeneratedColumn<int> episode = GeneratedColumn<int>(
      'episode', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _prefixMeta = const VerificationMeta('prefix');
  late final GeneratedColumn<String> prefix = GeneratedColumn<String>(
      'prefix', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _positionMsMeta =
      const VerificationMeta('positionMs');
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
      'position_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _durationMsMeta =
      const VerificationMeta('durationMs');
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
      'duration_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  static const VerificationMeta _savedAtMeta =
      const VerificationMeta('savedAt');
  late final GeneratedColumn<int> savedAt = GeneratedColumn<int>(
      'saved_at', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      $customConstraints: 'NOT NULL');
  @override
  List<GeneratedColumn> get $columns =>
      [mediaId, episode, prefix, positionMs, durationMs, savedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playback_positions';
  @override
  VerificationContext validateIntegrity(Insertable<PlaybackPosition> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_id')) {
      context.handle(_mediaIdMeta,
          mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta));
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('episode')) {
      context.handle(_episodeMeta,
          episode.isAcceptableOrUnknown(data['episode']!, _episodeMeta));
    } else if (isInserting) {
      context.missing(_episodeMeta);
    }
    if (data.containsKey('prefix')) {
      context.handle(_prefixMeta,
          prefix.isAcceptableOrUnknown(data['prefix']!, _prefixMeta));
    } else if (isInserting) {
      context.missing(_prefixMeta);
    }
    if (data.containsKey('position_ms')) {
      context.handle(
          _positionMsMeta,
          positionMs.isAcceptableOrUnknown(
              data['position_ms']!, _positionMsMeta));
    } else if (isInserting) {
      context.missing(_positionMsMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
          _durationMsMeta,
          durationMs.isAcceptableOrUnknown(
              data['duration_ms']!, _durationMsMeta));
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('saved_at')) {
      context.handle(_savedAtMeta,
          savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta));
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mediaId, episode};
  @override
  PlaybackPosition map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaybackPosition(
      mediaId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}media_id'])!,
      episode: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}episode'])!,
      prefix: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}prefix'])!,
      positionMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position_ms'])!,
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms'])!,
      savedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}saved_at'])!,
    );
  }

  @override
  PlaybackPositions createAlias(String alias) {
    return PlaybackPositions(attachedDatabase, alias);
  }

  @override
  List<String> get customConstraints =>
      const ['PRIMARY KEY(media_id, episode)'];
  @override
  bool get dontWriteConstraints => true;
}

class PlaybackPosition extends DataClass
    implements Insertable<PlaybackPosition> {
  final String mediaId;
  final int episode;
  final String prefix;

  /// 'anime_' or 'movie_'
  final int positionMs;
  final int durationMs;
  final int savedAt;
  const PlaybackPosition(
      {required this.mediaId,
      required this.episode,
      required this.prefix,
      required this.positionMs,
      required this.durationMs,
      required this.savedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_id'] = Variable<String>(mediaId);
    map['episode'] = Variable<int>(episode);
    map['prefix'] = Variable<String>(prefix);
    map['position_ms'] = Variable<int>(positionMs);
    map['duration_ms'] = Variable<int>(durationMs);
    map['saved_at'] = Variable<int>(savedAt);
    return map;
  }

  PlaybackPositionsCompanion toCompanion(bool nullToAbsent) {
    return PlaybackPositionsCompanion(
      mediaId: Value(mediaId),
      episode: Value(episode),
      prefix: Value(prefix),
      positionMs: Value(positionMs),
      durationMs: Value(durationMs),
      savedAt: Value(savedAt),
    );
  }

  factory PlaybackPosition.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaybackPosition(
      mediaId: serializer.fromJson<String>(json['media_id']),
      episode: serializer.fromJson<int>(json['episode']),
      prefix: serializer.fromJson<String>(json['prefix']),
      positionMs: serializer.fromJson<int>(json['position_ms']),
      durationMs: serializer.fromJson<int>(json['duration_ms']),
      savedAt: serializer.fromJson<int>(json['saved_at']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'media_id': serializer.toJson<String>(mediaId),
      'episode': serializer.toJson<int>(episode),
      'prefix': serializer.toJson<String>(prefix),
      'position_ms': serializer.toJson<int>(positionMs),
      'duration_ms': serializer.toJson<int>(durationMs),
      'saved_at': serializer.toJson<int>(savedAt),
    };
  }

  PlaybackPosition copyWith(
          {String? mediaId,
          int? episode,
          String? prefix,
          int? positionMs,
          int? durationMs,
          int? savedAt}) =>
      PlaybackPosition(
        mediaId: mediaId ?? this.mediaId,
        episode: episode ?? this.episode,
        prefix: prefix ?? this.prefix,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        savedAt: savedAt ?? this.savedAt,
      );
  PlaybackPosition copyWithCompanion(PlaybackPositionsCompanion data) {
    return PlaybackPosition(
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      episode: data.episode.present ? data.episode.value : this.episode,
      prefix: data.prefix.present ? data.prefix.value : this.prefix,
      positionMs:
          data.positionMs.present ? data.positionMs.value : this.positionMs,
      durationMs:
          data.durationMs.present ? data.durationMs.value : this.durationMs,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackPosition(')
          ..write('mediaId: $mediaId, ')
          ..write('episode: $episode, ')
          ..write('prefix: $prefix, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('savedAt: $savedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(mediaId, episode, prefix, positionMs, durationMs, savedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaybackPosition &&
          other.mediaId == this.mediaId &&
          other.episode == this.episode &&
          other.prefix == this.prefix &&
          other.positionMs == this.positionMs &&
          other.durationMs == this.durationMs &&
          other.savedAt == this.savedAt);
}

class PlaybackPositionsCompanion extends UpdateCompanion<PlaybackPosition> {
  final Value<String> mediaId;
  final Value<int> episode;
  final Value<String> prefix;
  final Value<int> positionMs;
  final Value<int> durationMs;
  final Value<int> savedAt;
  final Value<int> rowid;
  const PlaybackPositionsCompanion({
    this.mediaId = const Value.absent(),
    this.episode = const Value.absent(),
    this.prefix = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaybackPositionsCompanion.insert({
    required String mediaId,
    required int episode,
    required String prefix,
    required int positionMs,
    required int durationMs,
    required int savedAt,
    this.rowid = const Value.absent(),
  })  : mediaId = Value(mediaId),
        episode = Value(episode),
        prefix = Value(prefix),
        positionMs = Value(positionMs),
        durationMs = Value(durationMs),
        savedAt = Value(savedAt);
  static Insertable<PlaybackPosition> custom({
    Expression<String>? mediaId,
    Expression<int>? episode,
    Expression<String>? prefix,
    Expression<int>? positionMs,
    Expression<int>? durationMs,
    Expression<int>? savedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaId != null) 'media_id': mediaId,
      if (episode != null) 'episode': episode,
      if (prefix != null) 'prefix': prefix,
      if (positionMs != null) 'position_ms': positionMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (savedAt != null) 'saved_at': savedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaybackPositionsCompanion copyWith(
      {Value<String>? mediaId,
      Value<int>? episode,
      Value<String>? prefix,
      Value<int>? positionMs,
      Value<int>? durationMs,
      Value<int>? savedAt,
      Value<int>? rowid}) {
    return PlaybackPositionsCompanion(
      mediaId: mediaId ?? this.mediaId,
      episode: episode ?? this.episode,
      prefix: prefix ?? this.prefix,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      savedAt: savedAt ?? this.savedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (episode.present) {
      map['episode'] = Variable<int>(episode.value);
    }
    if (prefix.present) {
      map['prefix'] = Variable<String>(prefix.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<int>(savedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaybackPositionsCompanion(')
          ..write('mediaId: $mediaId, ')
          ..write('episode: $episode, ')
          ..write('prefix: $prefix, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('savedAt: $savedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class LibraryFts extends Table
    with
        TableInfo<LibraryFts, LibraryFt>,
        VirtualTableInfo<LibraryFts, LibraryFt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  LibraryFts(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaIdMeta =
      const VerificationMeta('mediaId');
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
      'media_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: '');
  static const VerificationMeta _mediaModeMeta =
      const VerificationMeta('mediaMode');
  late final GeneratedColumn<String> mediaMode = GeneratedColumn<String>(
      'media_mode', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: '');
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: '');
  static const VerificationMeta _synonymsMeta =
      const VerificationMeta('synonyms');
  late final GeneratedColumn<String> synonyms = GeneratedColumn<String>(
      'synonyms', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      $customConstraints: '');
  @override
  List<GeneratedColumn> get $columns => [mediaId, mediaMode, title, synonyms];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_fts';
  @override
  VerificationContext validateIntegrity(Insertable<LibraryFt> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_id')) {
      context.handle(_mediaIdMeta,
          mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta));
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('media_mode')) {
      context.handle(_mediaModeMeta,
          mediaMode.isAcceptableOrUnknown(data['media_mode']!, _mediaModeMeta));
    } else if (isInserting) {
      context.missing(_mediaModeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('synonyms')) {
      context.handle(_synonymsMeta,
          synonyms.isAcceptableOrUnknown(data['synonyms']!, _synonymsMeta));
    } else if (isInserting) {
      context.missing(_synonymsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  LibraryFt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryFt(
      mediaId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}media_id'])!,
      mediaMode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}media_mode'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      synonyms: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}synonyms'])!,
    );
  }

  @override
  LibraryFts createAlias(String alias) {
    return LibraryFts(attachedDatabase, alias);
  }

  @override
  bool get dontWriteConstraints => true;
  @override
  String get moduleAndArgs => 'fts5(media_id, media_mode, title, synonyms)';
}

class LibraryFt extends DataClass implements Insertable<LibraryFt> {
  final String mediaId;
  final String mediaMode;
  final String title;
  final String synonyms;
  const LibraryFt(
      {required this.mediaId,
      required this.mediaMode,
      required this.title,
      required this.synonyms});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_id'] = Variable<String>(mediaId);
    map['media_mode'] = Variable<String>(mediaMode);
    map['title'] = Variable<String>(title);
    map['synonyms'] = Variable<String>(synonyms);
    return map;
  }

  LibraryFtsCompanion toCompanion(bool nullToAbsent) {
    return LibraryFtsCompanion(
      mediaId: Value(mediaId),
      mediaMode: Value(mediaMode),
      title: Value(title),
      synonyms: Value(synonyms),
    );
  }

  factory LibraryFt.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryFt(
      mediaId: serializer.fromJson<String>(json['media_id']),
      mediaMode: serializer.fromJson<String>(json['media_mode']),
      title: serializer.fromJson<String>(json['title']),
      synonyms: serializer.fromJson<String>(json['synonyms']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'media_id': serializer.toJson<String>(mediaId),
      'media_mode': serializer.toJson<String>(mediaMode),
      'title': serializer.toJson<String>(title),
      'synonyms': serializer.toJson<String>(synonyms),
    };
  }

  LibraryFt copyWith(
          {String? mediaId,
          String? mediaMode,
          String? title,
          String? synonyms}) =>
      LibraryFt(
        mediaId: mediaId ?? this.mediaId,
        mediaMode: mediaMode ?? this.mediaMode,
        title: title ?? this.title,
        synonyms: synonyms ?? this.synonyms,
      );
  LibraryFt copyWithCompanion(LibraryFtsCompanion data) {
    return LibraryFt(
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      mediaMode: data.mediaMode.present ? data.mediaMode.value : this.mediaMode,
      title: data.title.present ? data.title.value : this.title,
      synonyms: data.synonyms.present ? data.synonyms.value : this.synonyms,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryFt(')
          ..write('mediaId: $mediaId, ')
          ..write('mediaMode: $mediaMode, ')
          ..write('title: $title, ')
          ..write('synonyms: $synonyms')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mediaId, mediaMode, title, synonyms);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryFt &&
          other.mediaId == this.mediaId &&
          other.mediaMode == this.mediaMode &&
          other.title == this.title &&
          other.synonyms == this.synonyms);
}

class LibraryFtsCompanion extends UpdateCompanion<LibraryFt> {
  final Value<String> mediaId;
  final Value<String> mediaMode;
  final Value<String> title;
  final Value<String> synonyms;
  final Value<int> rowid;
  const LibraryFtsCompanion({
    this.mediaId = const Value.absent(),
    this.mediaMode = const Value.absent(),
    this.title = const Value.absent(),
    this.synonyms = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LibraryFtsCompanion.insert({
    required String mediaId,
    required String mediaMode,
    required String title,
    required String synonyms,
    this.rowid = const Value.absent(),
  })  : mediaId = Value(mediaId),
        mediaMode = Value(mediaMode),
        title = Value(title),
        synonyms = Value(synonyms);
  static Insertable<LibraryFt> custom({
    Expression<String>? mediaId,
    Expression<String>? mediaMode,
    Expression<String>? title,
    Expression<String>? synonyms,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaId != null) 'media_id': mediaId,
      if (mediaMode != null) 'media_mode': mediaMode,
      if (title != null) 'title': title,
      if (synonyms != null) 'synonyms': synonyms,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LibraryFtsCompanion copyWith(
      {Value<String>? mediaId,
      Value<String>? mediaMode,
      Value<String>? title,
      Value<String>? synonyms,
      Value<int>? rowid}) {
    return LibraryFtsCompanion(
      mediaId: mediaId ?? this.mediaId,
      mediaMode: mediaMode ?? this.mediaMode,
      title: title ?? this.title,
      synonyms: synonyms ?? this.synonyms,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (mediaMode.present) {
      map['media_mode'] = Variable<String>(mediaMode.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (synonyms.present) {
      map['synonyms'] = Variable<String>(synonyms.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibraryFtsCompanion(')
          ..write('mediaId: $mediaId, ')
          ..write('mediaMode: $mediaMode, ')
          ..write('title: $title, ')
          ..write('synonyms: $synonyms, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final LibraryItems libraryItems = LibraryItems(this);
  late final LibraryCategories libraryCategories = LibraryCategories(this);
  late final MediaCaches mediaCaches = MediaCaches(this);
  late final NotificationAcks notificationAcks = NotificationAcks(this);
  late final WatchHistory watchHistory = WatchHistory(this);
  late final Index idxWatchHistoryTimestamp = Index(
      'idx_watch_history_timestamp',
      'CREATE INDEX idx_watch_history_timestamp ON watch_history (timestamp DESC)');
  late final ContinueWatching continueWatching = ContinueWatching(this);
  late final Index idxContinueWatchingTimestamp = Index(
      'idx_continue_watching_timestamp',
      'CREATE INDEX idx_continue_watching_timestamp ON continue_watching (timestamp DESC)');
  late final PlaybackPositions playbackPositions = PlaybackPositions(this);
  late final LibraryFts libraryFts = LibraryFts(this);
  late final Trigger mediaCachesInsertFts = Trigger(
      'CREATE TRIGGER media_caches_insert_fts AFTER INSERT ON media_caches BEGIN INSERT INTO library_fts (media_id, media_mode, title, synonyms) VALUES (new.id, new.mode, new.title, new.extra_data);END',
      'media_caches_insert_fts');
  late final Trigger mediaCachesDeleteFts = Trigger(
      'CREATE TRIGGER media_caches_delete_fts AFTER DELETE ON media_caches BEGIN DELETE FROM library_fts WHERE media_id = old.id AND media_mode = old.mode;END',
      'media_caches_delete_fts');
  late final Trigger mediaCachesUpdateFts = Trigger(
      'CREATE TRIGGER media_caches_update_fts AFTER UPDATE ON media_caches BEGIN DELETE FROM library_fts WHERE media_id = old.id AND media_mode = old.mode;INSERT INTO library_fts (media_id, media_mode, title, synonyms) VALUES (new.id, new.mode, new.title, new.extra_data);END',
      'media_caches_update_fts');
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        libraryItems,
        libraryCategories,
        mediaCaches,
        notificationAcks,
        watchHistory,
        idxWatchHistoryTimestamp,
        continueWatching,
        idxContinueWatchingTimestamp,
        playbackPositions,
        libraryFts,
        mediaCachesInsertFts,
        mediaCachesDeleteFts,
        mediaCachesUpdateFts
      ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('media_caches',
                limitUpdateKind: UpdateKind.insert),
            result: [
              TableUpdate('library_fts', kind: UpdateKind.insert),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('media_caches',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('library_fts', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('media_caches',
                limitUpdateKind: UpdateKind.update),
            result: [
              TableUpdate('library_fts', kind: UpdateKind.delete),
              TableUpdate('library_fts', kind: UpdateKind.insert),
            ],
          ),
        ],
      );
}

typedef $LibraryItemsCreateCompanionBuilder = LibraryItemsCompanion Function({
  required int id,
  required String mode,
  required String format,
  required String libraryStatus,
  required double rating,
  required int watchedEpisodes,
  Value<int?> totalEpisodes,
  required DateTime addedAt,
  required String categoryIds,
  Value<int> rowid,
});
typedef $LibraryItemsUpdateCompanionBuilder = LibraryItemsCompanion Function({
  Value<int> id,
  Value<String> mode,
  Value<String> format,
  Value<String> libraryStatus,
  Value<double> rating,
  Value<int> watchedEpisodes,
  Value<int?> totalEpisodes,
  Value<DateTime> addedAt,
  Value<String> categoryIds,
  Value<int> rowid,
});

class $LibraryItemsFilterComposer
    extends Composer<_$AppDatabase, LibraryItems> {
  $LibraryItemsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mode => $composableBuilder(
      column: $table.mode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get format => $composableBuilder(
      column: $table.format, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get libraryStatus => $composableBuilder(
      column: $table.libraryStatus, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get rating => $composableBuilder(
      column: $table.rating, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get watchedEpisodes => $composableBuilder(
      column: $table.watchedEpisodes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalEpisodes => $composableBuilder(
      column: $table.totalEpisodes, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get categoryIds => $composableBuilder(
      column: $table.categoryIds, builder: (column) => ColumnFilters(column));
}

class $LibraryItemsOrderingComposer
    extends Composer<_$AppDatabase, LibraryItems> {
  $LibraryItemsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mode => $composableBuilder(
      column: $table.mode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get format => $composableBuilder(
      column: $table.format, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get libraryStatus => $composableBuilder(
      column: $table.libraryStatus,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get rating => $composableBuilder(
      column: $table.rating, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get watchedEpisodes => $composableBuilder(
      column: $table.watchedEpisodes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalEpisodes => $composableBuilder(
      column: $table.totalEpisodes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get categoryIds => $composableBuilder(
      column: $table.categoryIds, builder: (column) => ColumnOrderings(column));
}

class $LibraryItemsAnnotationComposer
    extends Composer<_$AppDatabase, LibraryItems> {
  $LibraryItemsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<String> get libraryStatus => $composableBuilder(
      column: $table.libraryStatus, builder: (column) => column);

  GeneratedColumn<double> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<int> get watchedEpisodes => $composableBuilder(
      column: $table.watchedEpisodes, builder: (column) => column);

  GeneratedColumn<int> get totalEpisodes => $composableBuilder(
      column: $table.totalEpisodes, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<String> get categoryIds => $composableBuilder(
      column: $table.categoryIds, builder: (column) => column);
}

class $LibraryItemsTableManager extends RootTableManager<
    _$AppDatabase,
    LibraryItems,
    LibraryItem,
    $LibraryItemsFilterComposer,
    $LibraryItemsOrderingComposer,
    $LibraryItemsAnnotationComposer,
    $LibraryItemsCreateCompanionBuilder,
    $LibraryItemsUpdateCompanionBuilder,
    (LibraryItem, BaseReferences<_$AppDatabase, LibraryItems, LibraryItem>),
    LibraryItem,
    PrefetchHooks Function()> {
  $LibraryItemsTableManager(_$AppDatabase db, LibraryItems table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $LibraryItemsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $LibraryItemsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $LibraryItemsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> mode = const Value.absent(),
            Value<String> format = const Value.absent(),
            Value<String> libraryStatus = const Value.absent(),
            Value<double> rating = const Value.absent(),
            Value<int> watchedEpisodes = const Value.absent(),
            Value<int?> totalEpisodes = const Value.absent(),
            Value<DateTime> addedAt = const Value.absent(),
            Value<String> categoryIds = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LibraryItemsCompanion(
            id: id,
            mode: mode,
            format: format,
            libraryStatus: libraryStatus,
            rating: rating,
            watchedEpisodes: watchedEpisodes,
            totalEpisodes: totalEpisodes,
            addedAt: addedAt,
            categoryIds: categoryIds,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int id,
            required String mode,
            required String format,
            required String libraryStatus,
            required double rating,
            required int watchedEpisodes,
            Value<int?> totalEpisodes = const Value.absent(),
            required DateTime addedAt,
            required String categoryIds,
            Value<int> rowid = const Value.absent(),
          }) =>
              LibraryItemsCompanion.insert(
            id: id,
            mode: mode,
            format: format,
            libraryStatus: libraryStatus,
            rating: rating,
            watchedEpisodes: watchedEpisodes,
            totalEpisodes: totalEpisodes,
            addedAt: addedAt,
            categoryIds: categoryIds,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $LibraryItemsProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    LibraryItems,
    LibraryItem,
    $LibraryItemsFilterComposer,
    $LibraryItemsOrderingComposer,
    $LibraryItemsAnnotationComposer,
    $LibraryItemsCreateCompanionBuilder,
    $LibraryItemsUpdateCompanionBuilder,
    (LibraryItem, BaseReferences<_$AppDatabase, LibraryItems, LibraryItem>),
    LibraryItem,
    PrefetchHooks Function()>;
typedef $LibraryCategoriesCreateCompanionBuilder = LibraryCategoriesCompanion
    Function({
  required String id,
  required String name,
  required String mode,
  Value<int> rowid,
});
typedef $LibraryCategoriesUpdateCompanionBuilder = LibraryCategoriesCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<String> mode,
  Value<int> rowid,
});

class $LibraryCategoriesFilterComposer
    extends Composer<_$AppDatabase, LibraryCategories> {
  $LibraryCategoriesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mode => $composableBuilder(
      column: $table.mode, builder: (column) => ColumnFilters(column));
}

class $LibraryCategoriesOrderingComposer
    extends Composer<_$AppDatabase, LibraryCategories> {
  $LibraryCategoriesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mode => $composableBuilder(
      column: $table.mode, builder: (column) => ColumnOrderings(column));
}

class $LibraryCategoriesAnnotationComposer
    extends Composer<_$AppDatabase, LibraryCategories> {
  $LibraryCategoriesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);
}

class $LibraryCategoriesTableManager extends RootTableManager<
    _$AppDatabase,
    LibraryCategories,
    LibraryCategory,
    $LibraryCategoriesFilterComposer,
    $LibraryCategoriesOrderingComposer,
    $LibraryCategoriesAnnotationComposer,
    $LibraryCategoriesCreateCompanionBuilder,
    $LibraryCategoriesUpdateCompanionBuilder,
    (
      LibraryCategory,
      BaseReferences<_$AppDatabase, LibraryCategories, LibraryCategory>
    ),
    LibraryCategory,
    PrefetchHooks Function()> {
  $LibraryCategoriesTableManager(_$AppDatabase db, LibraryCategories table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $LibraryCategoriesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $LibraryCategoriesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $LibraryCategoriesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> mode = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LibraryCategoriesCompanion(
            id: id,
            name: name,
            mode: mode,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String mode,
            Value<int> rowid = const Value.absent(),
          }) =>
              LibraryCategoriesCompanion.insert(
            id: id,
            name: name,
            mode: mode,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $LibraryCategoriesProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    LibraryCategories,
    LibraryCategory,
    $LibraryCategoriesFilterComposer,
    $LibraryCategoriesOrderingComposer,
    $LibraryCategoriesAnnotationComposer,
    $LibraryCategoriesCreateCompanionBuilder,
    $LibraryCategoriesUpdateCompanionBuilder,
    (
      LibraryCategory,
      BaseReferences<_$AppDatabase, LibraryCategories, LibraryCategory>
    ),
    LibraryCategory,
    PrefetchHooks Function()>;
typedef $MediaCachesCreateCompanionBuilder = MediaCachesCompanion Function({
  required int id,
  required String mode,
  required String title,
  required String coverImage,
  Value<int?> averageScore,
  Value<String?> format,
  Value<String?> status,
  Value<String?> bannerImage,
  Value<String?> extraData,
  Value<int> rowid,
});
typedef $MediaCachesUpdateCompanionBuilder = MediaCachesCompanion Function({
  Value<int> id,
  Value<String> mode,
  Value<String> title,
  Value<String> coverImage,
  Value<int?> averageScore,
  Value<String?> format,
  Value<String?> status,
  Value<String?> bannerImage,
  Value<String?> extraData,
  Value<int> rowid,
});

class $MediaCachesFilterComposer extends Composer<_$AppDatabase, MediaCaches> {
  $MediaCachesFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mode => $composableBuilder(
      column: $table.mode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get coverImage => $composableBuilder(
      column: $table.coverImage, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get averageScore => $composableBuilder(
      column: $table.averageScore, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get format => $composableBuilder(
      column: $table.format, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get bannerImage => $composableBuilder(
      column: $table.bannerImage, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get extraData => $composableBuilder(
      column: $table.extraData, builder: (column) => ColumnFilters(column));
}

class $MediaCachesOrderingComposer
    extends Composer<_$AppDatabase, MediaCaches> {
  $MediaCachesOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mode => $composableBuilder(
      column: $table.mode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get coverImage => $composableBuilder(
      column: $table.coverImage, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get averageScore => $composableBuilder(
      column: $table.averageScore,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get format => $composableBuilder(
      column: $table.format, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get bannerImage => $composableBuilder(
      column: $table.bannerImage, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get extraData => $composableBuilder(
      column: $table.extraData, builder: (column) => ColumnOrderings(column));
}

class $MediaCachesAnnotationComposer
    extends Composer<_$AppDatabase, MediaCaches> {
  $MediaCachesAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get coverImage => $composableBuilder(
      column: $table.coverImage, builder: (column) => column);

  GeneratedColumn<int> get averageScore => $composableBuilder(
      column: $table.averageScore, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get bannerImage => $composableBuilder(
      column: $table.bannerImage, builder: (column) => column);

  GeneratedColumn<String> get extraData =>
      $composableBuilder(column: $table.extraData, builder: (column) => column);
}

class $MediaCachesTableManager extends RootTableManager<
    _$AppDatabase,
    MediaCaches,
    MediaCache,
    $MediaCachesFilterComposer,
    $MediaCachesOrderingComposer,
    $MediaCachesAnnotationComposer,
    $MediaCachesCreateCompanionBuilder,
    $MediaCachesUpdateCompanionBuilder,
    (MediaCache, BaseReferences<_$AppDatabase, MediaCaches, MediaCache>),
    MediaCache,
    PrefetchHooks Function()> {
  $MediaCachesTableManager(_$AppDatabase db, MediaCaches table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $MediaCachesFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $MediaCachesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $MediaCachesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> mode = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> coverImage = const Value.absent(),
            Value<int?> averageScore = const Value.absent(),
            Value<String?> format = const Value.absent(),
            Value<String?> status = const Value.absent(),
            Value<String?> bannerImage = const Value.absent(),
            Value<String?> extraData = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaCachesCompanion(
            id: id,
            mode: mode,
            title: title,
            coverImage: coverImage,
            averageScore: averageScore,
            format: format,
            status: status,
            bannerImage: bannerImage,
            extraData: extraData,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required int id,
            required String mode,
            required String title,
            required String coverImage,
            Value<int?> averageScore = const Value.absent(),
            Value<String?> format = const Value.absent(),
            Value<String?> status = const Value.absent(),
            Value<String?> bannerImage = const Value.absent(),
            Value<String?> extraData = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaCachesCompanion.insert(
            id: id,
            mode: mode,
            title: title,
            coverImage: coverImage,
            averageScore: averageScore,
            format: format,
            status: status,
            bannerImage: bannerImage,
            extraData: extraData,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $MediaCachesProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    MediaCaches,
    MediaCache,
    $MediaCachesFilterComposer,
    $MediaCachesOrderingComposer,
    $MediaCachesAnnotationComposer,
    $MediaCachesCreateCompanionBuilder,
    $MediaCachesUpdateCompanionBuilder,
    (MediaCache, BaseReferences<_$AppDatabase, MediaCaches, MediaCache>),
    MediaCache,
    PrefetchHooks Function()>;
typedef $NotificationAcksCreateCompanionBuilder = NotificationAcksCompanion
    Function({
  required String mediaKey,
  required int ackValue,
  required int startValue,
  Value<int> rowid,
});
typedef $NotificationAcksUpdateCompanionBuilder = NotificationAcksCompanion
    Function({
  Value<String> mediaKey,
  Value<int> ackValue,
  Value<int> startValue,
  Value<int> rowid,
});

class $NotificationAcksFilterComposer
    extends Composer<_$AppDatabase, NotificationAcks> {
  $NotificationAcksFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mediaKey => $composableBuilder(
      column: $table.mediaKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ackValue => $composableBuilder(
      column: $table.ackValue, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startValue => $composableBuilder(
      column: $table.startValue, builder: (column) => ColumnFilters(column));
}

class $NotificationAcksOrderingComposer
    extends Composer<_$AppDatabase, NotificationAcks> {
  $NotificationAcksOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mediaKey => $composableBuilder(
      column: $table.mediaKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ackValue => $composableBuilder(
      column: $table.ackValue, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startValue => $composableBuilder(
      column: $table.startValue, builder: (column) => ColumnOrderings(column));
}

class $NotificationAcksAnnotationComposer
    extends Composer<_$AppDatabase, NotificationAcks> {
  $NotificationAcksAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mediaKey =>
      $composableBuilder(column: $table.mediaKey, builder: (column) => column);

  GeneratedColumn<int> get ackValue =>
      $composableBuilder(column: $table.ackValue, builder: (column) => column);

  GeneratedColumn<int> get startValue => $composableBuilder(
      column: $table.startValue, builder: (column) => column);
}

class $NotificationAcksTableManager extends RootTableManager<
    _$AppDatabase,
    NotificationAcks,
    NotificationAck,
    $NotificationAcksFilterComposer,
    $NotificationAcksOrderingComposer,
    $NotificationAcksAnnotationComposer,
    $NotificationAcksCreateCompanionBuilder,
    $NotificationAcksUpdateCompanionBuilder,
    (
      NotificationAck,
      BaseReferences<_$AppDatabase, NotificationAcks, NotificationAck>
    ),
    NotificationAck,
    PrefetchHooks Function()> {
  $NotificationAcksTableManager(_$AppDatabase db, NotificationAcks table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $NotificationAcksFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $NotificationAcksOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $NotificationAcksAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> mediaKey = const Value.absent(),
            Value<int> ackValue = const Value.absent(),
            Value<int> startValue = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              NotificationAcksCompanion(
            mediaKey: mediaKey,
            ackValue: ackValue,
            startValue: startValue,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String mediaKey,
            required int ackValue,
            required int startValue,
            Value<int> rowid = const Value.absent(),
          }) =>
              NotificationAcksCompanion.insert(
            mediaKey: mediaKey,
            ackValue: ackValue,
            startValue: startValue,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $NotificationAcksProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    NotificationAcks,
    NotificationAck,
    $NotificationAcksFilterComposer,
    $NotificationAcksOrderingComposer,
    $NotificationAcksAnnotationComposer,
    $NotificationAcksCreateCompanionBuilder,
    $NotificationAcksUpdateCompanionBuilder,
    (
      NotificationAck,
      BaseReferences<_$AppDatabase, NotificationAcks, NotificationAck>
    ),
    NotificationAck,
    PrefetchHooks Function()>;
typedef $WatchHistoryCreateCompanionBuilder = WatchHistoryCompanion Function({
  required String mediaId,
  required int isAnime,
  required int isManga,
  required String title,
  required String coverImage,
  required String format,
  Value<double> averageScore,
  Value<int> totalEpisodes,
  Value<String> mediaTypeHint,
  required String episodes,
  required int timestamp,
  Value<int> rowid,
});
typedef $WatchHistoryUpdateCompanionBuilder = WatchHistoryCompanion Function({
  Value<String> mediaId,
  Value<int> isAnime,
  Value<int> isManga,
  Value<String> title,
  Value<String> coverImage,
  Value<String> format,
  Value<double> averageScore,
  Value<int> totalEpisodes,
  Value<String> mediaTypeHint,
  Value<String> episodes,
  Value<int> timestamp,
  Value<int> rowid,
});

class $WatchHistoryFilterComposer
    extends Composer<_$AppDatabase, WatchHistory> {
  $WatchHistoryFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mediaId => $composableBuilder(
      column: $table.mediaId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get isAnime => $composableBuilder(
      column: $table.isAnime, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get isManga => $composableBuilder(
      column: $table.isManga, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get coverImage => $composableBuilder(
      column: $table.coverImage, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get format => $composableBuilder(
      column: $table.format, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get averageScore => $composableBuilder(
      column: $table.averageScore, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalEpisodes => $composableBuilder(
      column: $table.totalEpisodes, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mediaTypeHint => $composableBuilder(
      column: $table.mediaTypeHint, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get episodes => $composableBuilder(
      column: $table.episodes, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnFilters(column));
}

class $WatchHistoryOrderingComposer
    extends Composer<_$AppDatabase, WatchHistory> {
  $WatchHistoryOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mediaId => $composableBuilder(
      column: $table.mediaId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get isAnime => $composableBuilder(
      column: $table.isAnime, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get isManga => $composableBuilder(
      column: $table.isManga, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get coverImage => $composableBuilder(
      column: $table.coverImage, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get format => $composableBuilder(
      column: $table.format, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get averageScore => $composableBuilder(
      column: $table.averageScore,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalEpisodes => $composableBuilder(
      column: $table.totalEpisodes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mediaTypeHint => $composableBuilder(
      column: $table.mediaTypeHint,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get episodes => $composableBuilder(
      column: $table.episodes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnOrderings(column));
}

class $WatchHistoryAnnotationComposer
    extends Composer<_$AppDatabase, WatchHistory> {
  $WatchHistoryAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<int> get isAnime =>
      $composableBuilder(column: $table.isAnime, builder: (column) => column);

  GeneratedColumn<int> get isManga =>
      $composableBuilder(column: $table.isManga, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get coverImage => $composableBuilder(
      column: $table.coverImage, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<double> get averageScore => $composableBuilder(
      column: $table.averageScore, builder: (column) => column);

  GeneratedColumn<int> get totalEpisodes => $composableBuilder(
      column: $table.totalEpisodes, builder: (column) => column);

  GeneratedColumn<String> get mediaTypeHint => $composableBuilder(
      column: $table.mediaTypeHint, builder: (column) => column);

  GeneratedColumn<String> get episodes =>
      $composableBuilder(column: $table.episodes, builder: (column) => column);

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);
}

class $WatchHistoryTableManager extends RootTableManager<
    _$AppDatabase,
    WatchHistory,
    WatchHistoryData,
    $WatchHistoryFilterComposer,
    $WatchHistoryOrderingComposer,
    $WatchHistoryAnnotationComposer,
    $WatchHistoryCreateCompanionBuilder,
    $WatchHistoryUpdateCompanionBuilder,
    (
      WatchHistoryData,
      BaseReferences<_$AppDatabase, WatchHistory, WatchHistoryData>
    ),
    WatchHistoryData,
    PrefetchHooks Function()> {
  $WatchHistoryTableManager(_$AppDatabase db, WatchHistory table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $WatchHistoryFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $WatchHistoryOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $WatchHistoryAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> mediaId = const Value.absent(),
            Value<int> isAnime = const Value.absent(),
            Value<int> isManga = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> coverImage = const Value.absent(),
            Value<String> format = const Value.absent(),
            Value<double> averageScore = const Value.absent(),
            Value<int> totalEpisodes = const Value.absent(),
            Value<String> mediaTypeHint = const Value.absent(),
            Value<String> episodes = const Value.absent(),
            Value<int> timestamp = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              WatchHistoryCompanion(
            mediaId: mediaId,
            isAnime: isAnime,
            isManga: isManga,
            title: title,
            coverImage: coverImage,
            format: format,
            averageScore: averageScore,
            totalEpisodes: totalEpisodes,
            mediaTypeHint: mediaTypeHint,
            episodes: episodes,
            timestamp: timestamp,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String mediaId,
            required int isAnime,
            required int isManga,
            required String title,
            required String coverImage,
            required String format,
            Value<double> averageScore = const Value.absent(),
            Value<int> totalEpisodes = const Value.absent(),
            Value<String> mediaTypeHint = const Value.absent(),
            required String episodes,
            required int timestamp,
            Value<int> rowid = const Value.absent(),
          }) =>
              WatchHistoryCompanion.insert(
            mediaId: mediaId,
            isAnime: isAnime,
            isManga: isManga,
            title: title,
            coverImage: coverImage,
            format: format,
            averageScore: averageScore,
            totalEpisodes: totalEpisodes,
            mediaTypeHint: mediaTypeHint,
            episodes: episodes,
            timestamp: timestamp,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $WatchHistoryProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    WatchHistory,
    WatchHistoryData,
    $WatchHistoryFilterComposer,
    $WatchHistoryOrderingComposer,
    $WatchHistoryAnnotationComposer,
    $WatchHistoryCreateCompanionBuilder,
    $WatchHistoryUpdateCompanionBuilder,
    (
      WatchHistoryData,
      BaseReferences<_$AppDatabase, WatchHistory, WatchHistoryData>
    ),
    WatchHistoryData,
    PrefetchHooks Function()>;
typedef $ContinueWatchingCreateCompanionBuilder = ContinueWatchingCompanion
    Function({
  required String mediaId,
  required String prefix,
  required String metadataJson,
  required int lastEpisode,
  required int timestamp,
  Value<int> rowid,
});
typedef $ContinueWatchingUpdateCompanionBuilder = ContinueWatchingCompanion
    Function({
  Value<String> mediaId,
  Value<String> prefix,
  Value<String> metadataJson,
  Value<int> lastEpisode,
  Value<int> timestamp,
  Value<int> rowid,
});

class $ContinueWatchingFilterComposer
    extends Composer<_$AppDatabase, ContinueWatching> {
  $ContinueWatchingFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mediaId => $composableBuilder(
      column: $table.mediaId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get prefix => $composableBuilder(
      column: $table.prefix, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get metadataJson => $composableBuilder(
      column: $table.metadataJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastEpisode => $composableBuilder(
      column: $table.lastEpisode, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnFilters(column));
}

class $ContinueWatchingOrderingComposer
    extends Composer<_$AppDatabase, ContinueWatching> {
  $ContinueWatchingOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mediaId => $composableBuilder(
      column: $table.mediaId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get prefix => $composableBuilder(
      column: $table.prefix, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get metadataJson => $composableBuilder(
      column: $table.metadataJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastEpisode => $composableBuilder(
      column: $table.lastEpisode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnOrderings(column));
}

class $ContinueWatchingAnnotationComposer
    extends Composer<_$AppDatabase, ContinueWatching> {
  $ContinueWatchingAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<String> get prefix =>
      $composableBuilder(column: $table.prefix, builder: (column) => column);

  GeneratedColumn<String> get metadataJson => $composableBuilder(
      column: $table.metadataJson, builder: (column) => column);

  GeneratedColumn<int> get lastEpisode => $composableBuilder(
      column: $table.lastEpisode, builder: (column) => column);

  GeneratedColumn<int> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);
}

class $ContinueWatchingTableManager extends RootTableManager<
    _$AppDatabase,
    ContinueWatching,
    ContinueWatchingData,
    $ContinueWatchingFilterComposer,
    $ContinueWatchingOrderingComposer,
    $ContinueWatchingAnnotationComposer,
    $ContinueWatchingCreateCompanionBuilder,
    $ContinueWatchingUpdateCompanionBuilder,
    (
      ContinueWatchingData,
      BaseReferences<_$AppDatabase, ContinueWatching, ContinueWatchingData>
    ),
    ContinueWatchingData,
    PrefetchHooks Function()> {
  $ContinueWatchingTableManager(_$AppDatabase db, ContinueWatching table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $ContinueWatchingFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $ContinueWatchingOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $ContinueWatchingAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> mediaId = const Value.absent(),
            Value<String> prefix = const Value.absent(),
            Value<String> metadataJson = const Value.absent(),
            Value<int> lastEpisode = const Value.absent(),
            Value<int> timestamp = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ContinueWatchingCompanion(
            mediaId: mediaId,
            prefix: prefix,
            metadataJson: metadataJson,
            lastEpisode: lastEpisode,
            timestamp: timestamp,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String mediaId,
            required String prefix,
            required String metadataJson,
            required int lastEpisode,
            required int timestamp,
            Value<int> rowid = const Value.absent(),
          }) =>
              ContinueWatchingCompanion.insert(
            mediaId: mediaId,
            prefix: prefix,
            metadataJson: metadataJson,
            lastEpisode: lastEpisode,
            timestamp: timestamp,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $ContinueWatchingProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    ContinueWatching,
    ContinueWatchingData,
    $ContinueWatchingFilterComposer,
    $ContinueWatchingOrderingComposer,
    $ContinueWatchingAnnotationComposer,
    $ContinueWatchingCreateCompanionBuilder,
    $ContinueWatchingUpdateCompanionBuilder,
    (
      ContinueWatchingData,
      BaseReferences<_$AppDatabase, ContinueWatching, ContinueWatchingData>
    ),
    ContinueWatchingData,
    PrefetchHooks Function()>;
typedef $PlaybackPositionsCreateCompanionBuilder = PlaybackPositionsCompanion
    Function({
  required String mediaId,
  required int episode,
  required String prefix,
  required int positionMs,
  required int durationMs,
  required int savedAt,
  Value<int> rowid,
});
typedef $PlaybackPositionsUpdateCompanionBuilder = PlaybackPositionsCompanion
    Function({
  Value<String> mediaId,
  Value<int> episode,
  Value<String> prefix,
  Value<int> positionMs,
  Value<int> durationMs,
  Value<int> savedAt,
  Value<int> rowid,
});

class $PlaybackPositionsFilterComposer
    extends Composer<_$AppDatabase, PlaybackPositions> {
  $PlaybackPositionsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mediaId => $composableBuilder(
      column: $table.mediaId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get episode => $composableBuilder(
      column: $table.episode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get prefix => $composableBuilder(
      column: $table.prefix, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get positionMs => $composableBuilder(
      column: $table.positionMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get savedAt => $composableBuilder(
      column: $table.savedAt, builder: (column) => ColumnFilters(column));
}

class $PlaybackPositionsOrderingComposer
    extends Composer<_$AppDatabase, PlaybackPositions> {
  $PlaybackPositionsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mediaId => $composableBuilder(
      column: $table.mediaId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get episode => $composableBuilder(
      column: $table.episode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get prefix => $composableBuilder(
      column: $table.prefix, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get positionMs => $composableBuilder(
      column: $table.positionMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get savedAt => $composableBuilder(
      column: $table.savedAt, builder: (column) => ColumnOrderings(column));
}

class $PlaybackPositionsAnnotationComposer
    extends Composer<_$AppDatabase, PlaybackPositions> {
  $PlaybackPositionsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<int> get episode =>
      $composableBuilder(column: $table.episode, builder: (column) => column);

  GeneratedColumn<String> get prefix =>
      $composableBuilder(column: $table.prefix, builder: (column) => column);

  GeneratedColumn<int> get positionMs => $composableBuilder(
      column: $table.positionMs, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => column);

  GeneratedColumn<int> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);
}

class $PlaybackPositionsTableManager extends RootTableManager<
    _$AppDatabase,
    PlaybackPositions,
    PlaybackPosition,
    $PlaybackPositionsFilterComposer,
    $PlaybackPositionsOrderingComposer,
    $PlaybackPositionsAnnotationComposer,
    $PlaybackPositionsCreateCompanionBuilder,
    $PlaybackPositionsUpdateCompanionBuilder,
    (
      PlaybackPosition,
      BaseReferences<_$AppDatabase, PlaybackPositions, PlaybackPosition>
    ),
    PlaybackPosition,
    PrefetchHooks Function()> {
  $PlaybackPositionsTableManager(_$AppDatabase db, PlaybackPositions table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $PlaybackPositionsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $PlaybackPositionsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $PlaybackPositionsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> mediaId = const Value.absent(),
            Value<int> episode = const Value.absent(),
            Value<String> prefix = const Value.absent(),
            Value<int> positionMs = const Value.absent(),
            Value<int> durationMs = const Value.absent(),
            Value<int> savedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PlaybackPositionsCompanion(
            mediaId: mediaId,
            episode: episode,
            prefix: prefix,
            positionMs: positionMs,
            durationMs: durationMs,
            savedAt: savedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String mediaId,
            required int episode,
            required String prefix,
            required int positionMs,
            required int durationMs,
            required int savedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              PlaybackPositionsCompanion.insert(
            mediaId: mediaId,
            episode: episode,
            prefix: prefix,
            positionMs: positionMs,
            durationMs: durationMs,
            savedAt: savedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $PlaybackPositionsProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    PlaybackPositions,
    PlaybackPosition,
    $PlaybackPositionsFilterComposer,
    $PlaybackPositionsOrderingComposer,
    $PlaybackPositionsAnnotationComposer,
    $PlaybackPositionsCreateCompanionBuilder,
    $PlaybackPositionsUpdateCompanionBuilder,
    (
      PlaybackPosition,
      BaseReferences<_$AppDatabase, PlaybackPositions, PlaybackPosition>
    ),
    PlaybackPosition,
    PrefetchHooks Function()>;
typedef $LibraryFtsCreateCompanionBuilder = LibraryFtsCompanion Function({
  required String mediaId,
  required String mediaMode,
  required String title,
  required String synonyms,
  Value<int> rowid,
});
typedef $LibraryFtsUpdateCompanionBuilder = LibraryFtsCompanion Function({
  Value<String> mediaId,
  Value<String> mediaMode,
  Value<String> title,
  Value<String> synonyms,
  Value<int> rowid,
});

class $LibraryFtsFilterComposer extends Composer<_$AppDatabase, LibraryFts> {
  $LibraryFtsFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mediaId => $composableBuilder(
      column: $table.mediaId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mediaMode => $composableBuilder(
      column: $table.mediaMode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get synonyms => $composableBuilder(
      column: $table.synonyms, builder: (column) => ColumnFilters(column));
}

class $LibraryFtsOrderingComposer extends Composer<_$AppDatabase, LibraryFts> {
  $LibraryFtsOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mediaId => $composableBuilder(
      column: $table.mediaId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mediaMode => $composableBuilder(
      column: $table.mediaMode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get synonyms => $composableBuilder(
      column: $table.synonyms, builder: (column) => ColumnOrderings(column));
}

class $LibraryFtsAnnotationComposer
    extends Composer<_$AppDatabase, LibraryFts> {
  $LibraryFtsAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<String> get mediaMode =>
      $composableBuilder(column: $table.mediaMode, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get synonyms =>
      $composableBuilder(column: $table.synonyms, builder: (column) => column);
}

class $LibraryFtsTableManager extends RootTableManager<
    _$AppDatabase,
    LibraryFts,
    LibraryFt,
    $LibraryFtsFilterComposer,
    $LibraryFtsOrderingComposer,
    $LibraryFtsAnnotationComposer,
    $LibraryFtsCreateCompanionBuilder,
    $LibraryFtsUpdateCompanionBuilder,
    (LibraryFt, BaseReferences<_$AppDatabase, LibraryFts, LibraryFt>),
    LibraryFt,
    PrefetchHooks Function()> {
  $LibraryFtsTableManager(_$AppDatabase db, LibraryFts table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $LibraryFtsFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $LibraryFtsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $LibraryFtsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> mediaId = const Value.absent(),
            Value<String> mediaMode = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> synonyms = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LibraryFtsCompanion(
            mediaId: mediaId,
            mediaMode: mediaMode,
            title: title,
            synonyms: synonyms,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String mediaId,
            required String mediaMode,
            required String title,
            required String synonyms,
            Value<int> rowid = const Value.absent(),
          }) =>
              LibraryFtsCompanion.insert(
            mediaId: mediaId,
            mediaMode: mediaMode,
            title: title,
            synonyms: synonyms,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $LibraryFtsProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    LibraryFts,
    LibraryFt,
    $LibraryFtsFilterComposer,
    $LibraryFtsOrderingComposer,
    $LibraryFtsAnnotationComposer,
    $LibraryFtsCreateCompanionBuilder,
    $LibraryFtsUpdateCompanionBuilder,
    (LibraryFt, BaseReferences<_$AppDatabase, LibraryFts, LibraryFt>),
    LibraryFt,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $LibraryItemsTableManager get libraryItems =>
      $LibraryItemsTableManager(_db, _db.libraryItems);
  $LibraryCategoriesTableManager get libraryCategories =>
      $LibraryCategoriesTableManager(_db, _db.libraryCategories);
  $MediaCachesTableManager get mediaCaches =>
      $MediaCachesTableManager(_db, _db.mediaCaches);
  $NotificationAcksTableManager get notificationAcks =>
      $NotificationAcksTableManager(_db, _db.notificationAcks);
  $WatchHistoryTableManager get watchHistory =>
      $WatchHistoryTableManager(_db, _db.watchHistory);
  $ContinueWatchingTableManager get continueWatching =>
      $ContinueWatchingTableManager(_db, _db.continueWatching);
  $PlaybackPositionsTableManager get playbackPositions =>
      $PlaybackPositionsTableManager(_db, _db.playbackPositions);
  $LibraryFtsTableManager get libraryFts =>
      $LibraryFtsTableManager(_db, _db.libraryFts);
}
