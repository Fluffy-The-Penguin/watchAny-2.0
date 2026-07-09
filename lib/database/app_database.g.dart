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
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _libraryStatusMeta = const VerificationMeta(
    'libraryStatus',
  );
  late final GeneratedColumn<String> libraryStatus = GeneratedColumn<String>(
    'library_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  late final GeneratedColumn<double> rating = GeneratedColumn<double>(
    'rating',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _watchedEpisodesMeta = const VerificationMeta(
    'watchedEpisodes',
  );
  late final GeneratedColumn<int> watchedEpisodes = GeneratedColumn<int>(
    'watched_episodes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _totalEpisodesMeta = const VerificationMeta(
    'totalEpisodes',
  );
  late final GeneratedColumn<int> totalEpisodes = GeneratedColumn<int>(
    'total_episodes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _categoryIdsMeta = const VerificationMeta(
    'categoryIds',
  );
  late final GeneratedColumn<String> categoryIds = GeneratedColumn<String>(
    'category_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
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
    categoryIds,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<LibraryItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    } else if (isInserting) {
      context.missing(_formatMeta);
    }
    if (data.containsKey('library_status')) {
      context.handle(
        _libraryStatusMeta,
        libraryStatus.isAcceptableOrUnknown(
          data['library_status']!,
          _libraryStatusMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_libraryStatusMeta);
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    } else if (isInserting) {
      context.missing(_ratingMeta);
    }
    if (data.containsKey('watched_episodes')) {
      context.handle(
        _watchedEpisodesMeta,
        watchedEpisodes.isAcceptableOrUnknown(
          data['watched_episodes']!,
          _watchedEpisodesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_watchedEpisodesMeta);
    }
    if (data.containsKey('total_episodes')) {
      context.handle(
        _totalEpisodesMeta,
        totalEpisodes.isAcceptableOrUnknown(
          data['total_episodes']!,
          _totalEpisodesMeta,
        ),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('category_ids')) {
      context.handle(
        _categoryIdsMeta,
        categoryIds.isAcceptableOrUnknown(
          data['category_ids']!,
          _categoryIdsMeta,
        ),
      );
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
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      mode:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}mode'],
          )!,
      format:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}format'],
          )!,
      libraryStatus:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}library_status'],
          )!,
      rating:
          attachedDatabase.typeMapping.read(
            DriftSqlType.double,
            data['${effectivePrefix}rating'],
          )!,
      watchedEpisodes:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}watched_episodes'],
          )!,
      totalEpisodes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_episodes'],
      ),
      addedAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.dateTime,
            data['${effectivePrefix}added_at'],
          )!,
      categoryIds:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}category_ids'],
          )!,
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
  const LibraryItem({
    required this.id,
    required this.mode,
    required this.format,
    required this.libraryStatus,
    required this.rating,
    required this.watchedEpisodes,
    this.totalEpisodes,
    required this.addedAt,
    required this.categoryIds,
  });
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
      totalEpisodes:
          totalEpisodes == null && nullToAbsent
              ? const Value.absent()
              : Value(totalEpisodes),
      addedAt: Value(addedAt),
      categoryIds: Value(categoryIds),
    );
  }

  factory LibraryItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
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

  LibraryItem copyWith({
    int? id,
    String? mode,
    String? format,
    String? libraryStatus,
    double? rating,
    int? watchedEpisodes,
    Value<int?> totalEpisodes = const Value.absent(),
    DateTime? addedAt,
    String? categoryIds,
  }) => LibraryItem(
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
      libraryStatus:
          data.libraryStatus.present
              ? data.libraryStatus.value
              : this.libraryStatus,
      rating: data.rating.present ? data.rating.value : this.rating,
      watchedEpisodes:
          data.watchedEpisodes.present
              ? data.watchedEpisodes.value
              : this.watchedEpisodes,
      totalEpisodes:
          data.totalEpisodes.present
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
  int get hashCode => Object.hash(
    id,
    mode,
    format,
    libraryStatus,
    rating,
    watchedEpisodes,
    totalEpisodes,
    addedAt,
    categoryIds,
  );
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
  }) : id = Value(id),
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

  LibraryItemsCompanion copyWith({
    Value<int>? id,
    Value<String>? mode,
    Value<String>? format,
    Value<String>? libraryStatus,
    Value<double>? rating,
    Value<int>? watchedEpisodes,
    Value<int?>? totalEpisodes,
    Value<DateTime>? addedAt,
    Value<String>? categoryIds,
    Value<int>? rowid,
  }) {
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
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, mode];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<LibraryCategory> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
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
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      mode:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}mode'],
          )!,
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
  const LibraryCategory({
    required this.id,
    required this.name,
    required this.mode,
  });
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

  factory LibraryCategory.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
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
  }) : id = Value(id),
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

  LibraryCategoriesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? mode,
    Value<int>? rowid,
  }) {
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
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _coverImageMeta = const VerificationMeta(
    'coverImage',
  );
  late final GeneratedColumn<String> coverImage = GeneratedColumn<String>(
    'cover_image',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _averageScoreMeta = const VerificationMeta(
    'averageScore',
  );
  late final GeneratedColumn<int> averageScore = GeneratedColumn<int>(
    'average_score',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _bannerImageMeta = const VerificationMeta(
    'bannerImage',
  );
  late final GeneratedColumn<String> bannerImage = GeneratedColumn<String>(
    'banner_image',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
  static const VerificationMeta _extraDataMeta = const VerificationMeta(
    'extraData',
  );
  late final GeneratedColumn<String> extraData = GeneratedColumn<String>(
    'extra_data',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints: '',
  );
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
    extraData,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_caches';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaCache> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('cover_image')) {
      context.handle(
        _coverImageMeta,
        coverImage.isAcceptableOrUnknown(data['cover_image']!, _coverImageMeta),
      );
    } else if (isInserting) {
      context.missing(_coverImageMeta);
    }
    if (data.containsKey('average_score')) {
      context.handle(
        _averageScoreMeta,
        averageScore.isAcceptableOrUnknown(
          data['average_score']!,
          _averageScoreMeta,
        ),
      );
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('banner_image')) {
      context.handle(
        _bannerImageMeta,
        bannerImage.isAcceptableOrUnknown(
          data['banner_image']!,
          _bannerImageMeta,
        ),
      );
    }
    if (data.containsKey('extra_data')) {
      context.handle(
        _extraDataMeta,
        extraData.isAcceptableOrUnknown(data['extra_data']!, _extraDataMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, mode};
  @override
  MediaCache map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaCache(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}id'],
          )!,
      mode:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}mode'],
          )!,
      title:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}title'],
          )!,
      coverImage:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}cover_image'],
          )!,
      averageScore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}average_score'],
      ),
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
      bannerImage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}banner_image'],
      ),
      extraData: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extra_data'],
      ),
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
  const MediaCache({
    required this.id,
    required this.mode,
    required this.title,
    required this.coverImage,
    this.averageScore,
    this.format,
    this.status,
    this.bannerImage,
    this.extraData,
  });
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
      averageScore:
          averageScore == null && nullToAbsent
              ? const Value.absent()
              : Value(averageScore),
      format:
          format == null && nullToAbsent ? const Value.absent() : Value(format),
      status:
          status == null && nullToAbsent ? const Value.absent() : Value(status),
      bannerImage:
          bannerImage == null && nullToAbsent
              ? const Value.absent()
              : Value(bannerImage),
      extraData:
          extraData == null && nullToAbsent
              ? const Value.absent()
              : Value(extraData),
    );
  }

  factory MediaCache.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
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

  MediaCache copyWith({
    int? id,
    String? mode,
    String? title,
    String? coverImage,
    Value<int?> averageScore = const Value.absent(),
    Value<String?> format = const Value.absent(),
    Value<String?> status = const Value.absent(),
    Value<String?> bannerImage = const Value.absent(),
    Value<String?> extraData = const Value.absent(),
  }) => MediaCache(
    id: id ?? this.id,
    mode: mode ?? this.mode,
    title: title ?? this.title,
    coverImage: coverImage ?? this.coverImage,
    averageScore: averageScore.present ? averageScore.value : this.averageScore,
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
      averageScore:
          data.averageScore.present
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
  int get hashCode => Object.hash(
    id,
    mode,
    title,
    coverImage,
    averageScore,
    format,
    status,
    bannerImage,
    extraData,
  );
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
  }) : id = Value(id),
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

  MediaCachesCompanion copyWith({
    Value<int>? id,
    Value<String>? mode,
    Value<String>? title,
    Value<String>? coverImage,
    Value<int?>? averageScore,
    Value<String?>? format,
    Value<String?>? status,
    Value<String?>? bannerImage,
    Value<String?>? extraData,
    Value<int>? rowid,
  }) {
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
  static const VerificationMeta _mediaKeyMeta = const VerificationMeta(
    'mediaKey',
  );
  late final GeneratedColumn<String> mediaKey = GeneratedColumn<String>(
    'media_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL PRIMARY KEY',
  );
  static const VerificationMeta _ackValueMeta = const VerificationMeta(
    'ackValue',
  );
  late final GeneratedColumn<int> ackValue = GeneratedColumn<int>(
    'ack_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  static const VerificationMeta _startValueMeta = const VerificationMeta(
    'startValue',
  );
  late final GeneratedColumn<int> startValue = GeneratedColumn<int>(
    'start_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL',
  );
  @override
  List<GeneratedColumn> get $columns => [mediaKey, ackValue, startValue];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notification_acks';
  @override
  VerificationContext validateIntegrity(
    Insertable<NotificationAck> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_key')) {
      context.handle(
        _mediaKeyMeta,
        mediaKey.isAcceptableOrUnknown(data['media_key']!, _mediaKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaKeyMeta);
    }
    if (data.containsKey('ack_value')) {
      context.handle(
        _ackValueMeta,
        ackValue.isAcceptableOrUnknown(data['ack_value']!, _ackValueMeta),
      );
    } else if (isInserting) {
      context.missing(_ackValueMeta);
    }
    if (data.containsKey('start_value')) {
      context.handle(
        _startValueMeta,
        startValue.isAcceptableOrUnknown(data['start_value']!, _startValueMeta),
      );
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
      mediaKey:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}media_key'],
          )!,
      ackValue:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}ack_value'],
          )!,
      startValue:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}start_value'],
          )!,
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
  const NotificationAck({
    required this.mediaKey,
    required this.ackValue,
    required this.startValue,
  });
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

  factory NotificationAck.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
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

  NotificationAck copyWith({
    String? mediaKey,
    int? ackValue,
    int? startValue,
  }) => NotificationAck(
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
  }) : mediaKey = Value(mediaKey),
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

  NotificationAcksCompanion copyWith({
    Value<String>? mediaKey,
    Value<int>? ackValue,
    Value<int>? startValue,
    Value<int>? rowid,
  }) {
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

class LibraryFts extends Table
    with
        TableInfo<LibraryFts, LibraryFt>,
        VirtualTableInfo<LibraryFts, LibraryFt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  LibraryFts(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
    'media_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _mediaModeMeta = const VerificationMeta(
    'mediaMode',
  );
  late final GeneratedColumn<String> mediaMode = GeneratedColumn<String>(
    'media_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  static const VerificationMeta _synonymsMeta = const VerificationMeta(
    'synonyms',
  );
  late final GeneratedColumn<String> synonyms = GeneratedColumn<String>(
    'synonyms',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints: '',
  );
  @override
  List<GeneratedColumn> get $columns => [mediaId, mediaMode, title, synonyms];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_fts';
  @override
  VerificationContext validateIntegrity(
    Insertable<LibraryFt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('media_mode')) {
      context.handle(
        _mediaModeMeta,
        mediaMode.isAcceptableOrUnknown(data['media_mode']!, _mediaModeMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaModeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('synonyms')) {
      context.handle(
        _synonymsMeta,
        synonyms.isAcceptableOrUnknown(data['synonyms']!, _synonymsMeta),
      );
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
      mediaId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}media_id'],
          )!,
      mediaMode:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}media_mode'],
          )!,
      title:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}title'],
          )!,
      synonyms:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}synonyms'],
          )!,
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
  const LibraryFt({
    required this.mediaId,
    required this.mediaMode,
    required this.title,
    required this.synonyms,
  });
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

  factory LibraryFt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
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

  LibraryFt copyWith({
    String? mediaId,
    String? mediaMode,
    String? title,
    String? synonyms,
  }) => LibraryFt(
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
  }) : mediaId = Value(mediaId),
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

  LibraryFtsCompanion copyWith({
    Value<String>? mediaId,
    Value<String>? mediaMode,
    Value<String>? title,
    Value<String>? synonyms,
    Value<int>? rowid,
  }) {
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
  late final LibraryFts libraryFts = LibraryFts(this);
  late final Trigger mediaCachesInsertFts = Trigger(
    'CREATE TRIGGER media_caches_insert_fts AFTER INSERT ON media_caches BEGIN INSERT INTO library_fts (media_id, media_mode, title, synonyms) VALUES (new.id, new.mode, new.title, new.extra_data);END',
    'media_caches_insert_fts',
  );
  late final Trigger mediaCachesDeleteFts = Trigger(
    'CREATE TRIGGER media_caches_delete_fts AFTER DELETE ON media_caches BEGIN DELETE FROM library_fts WHERE media_id = old.id AND media_mode = old.mode;END',
    'media_caches_delete_fts',
  );
  late final Trigger mediaCachesUpdateFts = Trigger(
    'CREATE TRIGGER media_caches_update_fts AFTER UPDATE ON media_caches BEGIN DELETE FROM library_fts WHERE media_id = old.id AND media_mode = old.mode;INSERT INTO library_fts (media_id, media_mode, title, synonyms) VALUES (new.id, new.mode, new.title, new.extra_data);END',
    'media_caches_update_fts',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    libraryItems,
    libraryCategories,
    mediaCaches,
    notificationAcks,
    libraryFts,
    mediaCachesInsertFts,
    mediaCachesDeleteFts,
    mediaCachesUpdateFts,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'media_caches',
        limitUpdateKind: UpdateKind.insert,
      ),
      result: [TableUpdate('library_fts', kind: UpdateKind.insert)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'media_caches',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('library_fts', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'media_caches',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [
        TableUpdate('library_fts', kind: UpdateKind.delete),
        TableUpdate('library_fts', kind: UpdateKind.insert),
      ],
    ),
  ]);
}

typedef $LibraryItemsCreateCompanionBuilder =
    LibraryItemsCompanion Function({
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
typedef $LibraryItemsUpdateCompanionBuilder =
    LibraryItemsCompanion Function({
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
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get libraryStatus => $composableBuilder(
    column: $table.libraryStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get watchedEpisodes => $composableBuilder(
    column: $table.watchedEpisodes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalEpisodes => $composableBuilder(
    column: $table.totalEpisodes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryIds => $composableBuilder(
    column: $table.categoryIds,
    builder: (column) => ColumnFilters(column),
  );
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
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get libraryStatus => $composableBuilder(
    column: $table.libraryStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get watchedEpisodes => $composableBuilder(
    column: $table.watchedEpisodes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalEpisodes => $composableBuilder(
    column: $table.totalEpisodes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryIds => $composableBuilder(
    column: $table.categoryIds,
    builder: (column) => ColumnOrderings(column),
  );
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
    column: $table.libraryStatus,
    builder: (column) => column,
  );

  GeneratedColumn<double> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<int> get watchedEpisodes => $composableBuilder(
    column: $table.watchedEpisodes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalEpisodes => $composableBuilder(
    column: $table.totalEpisodes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<String> get categoryIds => $composableBuilder(
    column: $table.categoryIds,
    builder: (column) => column,
  );
}

class $LibraryItemsTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          LibraryItems,
          LibraryItem,
          $LibraryItemsFilterComposer,
          $LibraryItemsOrderingComposer,
          $LibraryItemsAnnotationComposer,
          $LibraryItemsCreateCompanionBuilder,
          $LibraryItemsUpdateCompanionBuilder,
          (
            LibraryItem,
            BaseReferences<_$AppDatabase, LibraryItems, LibraryItem>,
          ),
          LibraryItem,
          PrefetchHooks Function()
        > {
  $LibraryItemsTableManager(_$AppDatabase db, LibraryItems table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $LibraryItemsFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $LibraryItemsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $LibraryItemsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
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
              }) => LibraryItemsCompanion(
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
          createCompanionCallback:
              ({
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
              }) => LibraryItemsCompanion.insert(
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
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $LibraryItemsProcessedTableManager =
    ProcessedTableManager<
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
      PrefetchHooks Function()
    >;
typedef $LibraryCategoriesCreateCompanionBuilder =
    LibraryCategoriesCompanion Function({
      required String id,
      required String name,
      required String mode,
      Value<int> rowid,
    });
typedef $LibraryCategoriesUpdateCompanionBuilder =
    LibraryCategoriesCompanion Function({
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
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );
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
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );
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

class $LibraryCategoriesTableManager
    extends
        RootTableManager<
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
            BaseReferences<_$AppDatabase, LibraryCategories, LibraryCategory>,
          ),
          LibraryCategory,
          PrefetchHooks Function()
        > {
  $LibraryCategoriesTableManager(_$AppDatabase db, LibraryCategories table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $LibraryCategoriesFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $LibraryCategoriesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $LibraryCategoriesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryCategoriesCompanion(
                id: id,
                name: name,
                mode: mode,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String mode,
                Value<int> rowid = const Value.absent(),
              }) => LibraryCategoriesCompanion.insert(
                id: id,
                name: name,
                mode: mode,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $LibraryCategoriesProcessedTableManager =
    ProcessedTableManager<
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
        BaseReferences<_$AppDatabase, LibraryCategories, LibraryCategory>,
      ),
      LibraryCategory,
      PrefetchHooks Function()
    >;
typedef $MediaCachesCreateCompanionBuilder =
    MediaCachesCompanion Function({
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
typedef $MediaCachesUpdateCompanionBuilder =
    MediaCachesCompanion Function({
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
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverImage => $composableBuilder(
    column: $table.coverImage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get averageScore => $composableBuilder(
    column: $table.averageScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bannerImage => $composableBuilder(
    column: $table.bannerImage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extraData => $composableBuilder(
    column: $table.extraData,
    builder: (column) => ColumnFilters(column),
  );
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
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverImage => $composableBuilder(
    column: $table.coverImage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get averageScore => $composableBuilder(
    column: $table.averageScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bannerImage => $composableBuilder(
    column: $table.bannerImage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extraData => $composableBuilder(
    column: $table.extraData,
    builder: (column) => ColumnOrderings(column),
  );
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
    column: $table.coverImage,
    builder: (column) => column,
  );

  GeneratedColumn<int> get averageScore => $composableBuilder(
    column: $table.averageScore,
    builder: (column) => column,
  );

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get bannerImage => $composableBuilder(
    column: $table.bannerImage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get extraData =>
      $composableBuilder(column: $table.extraData, builder: (column) => column);
}

class $MediaCachesTableManager
    extends
        RootTableManager<
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
          PrefetchHooks Function()
        > {
  $MediaCachesTableManager(_$AppDatabase db, MediaCaches table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $MediaCachesFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $MediaCachesOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $MediaCachesAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
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
              }) => MediaCachesCompanion(
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
          createCompanionCallback:
              ({
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
              }) => MediaCachesCompanion.insert(
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
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $MediaCachesProcessedTableManager =
    ProcessedTableManager<
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
      PrefetchHooks Function()
    >;
typedef $NotificationAcksCreateCompanionBuilder =
    NotificationAcksCompanion Function({
      required String mediaKey,
      required int ackValue,
      required int startValue,
      Value<int> rowid,
    });
typedef $NotificationAcksUpdateCompanionBuilder =
    NotificationAcksCompanion Function({
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
    column: $table.mediaKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ackValue => $composableBuilder(
    column: $table.ackValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startValue => $composableBuilder(
    column: $table.startValue,
    builder: (column) => ColumnFilters(column),
  );
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
    column: $table.mediaKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ackValue => $composableBuilder(
    column: $table.ackValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startValue => $composableBuilder(
    column: $table.startValue,
    builder: (column) => ColumnOrderings(column),
  );
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
    column: $table.startValue,
    builder: (column) => column,
  );
}

class $NotificationAcksTableManager
    extends
        RootTableManager<
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
            BaseReferences<_$AppDatabase, NotificationAcks, NotificationAck>,
          ),
          NotificationAck,
          PrefetchHooks Function()
        > {
  $NotificationAcksTableManager(_$AppDatabase db, NotificationAcks table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $NotificationAcksFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $NotificationAcksOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $NotificationAcksAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> mediaKey = const Value.absent(),
                Value<int> ackValue = const Value.absent(),
                Value<int> startValue = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotificationAcksCompanion(
                mediaKey: mediaKey,
                ackValue: ackValue,
                startValue: startValue,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mediaKey,
                required int ackValue,
                required int startValue,
                Value<int> rowid = const Value.absent(),
              }) => NotificationAcksCompanion.insert(
                mediaKey: mediaKey,
                ackValue: ackValue,
                startValue: startValue,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $NotificationAcksProcessedTableManager =
    ProcessedTableManager<
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
        BaseReferences<_$AppDatabase, NotificationAcks, NotificationAck>,
      ),
      NotificationAck,
      PrefetchHooks Function()
    >;
typedef $LibraryFtsCreateCompanionBuilder =
    LibraryFtsCompanion Function({
      required String mediaId,
      required String mediaMode,
      required String title,
      required String synonyms,
      Value<int> rowid,
    });
typedef $LibraryFtsUpdateCompanionBuilder =
    LibraryFtsCompanion Function({
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
    column: $table.mediaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaMode => $composableBuilder(
    column: $table.mediaMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get synonyms => $composableBuilder(
    column: $table.synonyms,
    builder: (column) => ColumnFilters(column),
  );
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
    column: $table.mediaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaMode => $composableBuilder(
    column: $table.mediaMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get synonyms => $composableBuilder(
    column: $table.synonyms,
    builder: (column) => ColumnOrderings(column),
  );
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

class $LibraryFtsTableManager
    extends
        RootTableManager<
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
          PrefetchHooks Function()
        > {
  $LibraryFtsTableManager(_$AppDatabase db, LibraryFts table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $LibraryFtsFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $LibraryFtsOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $LibraryFtsAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> mediaId = const Value.absent(),
                Value<String> mediaMode = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> synonyms = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryFtsCompanion(
                mediaId: mediaId,
                mediaMode: mediaMode,
                title: title,
                synonyms: synonyms,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mediaId,
                required String mediaMode,
                required String title,
                required String synonyms,
                Value<int> rowid = const Value.absent(),
              }) => LibraryFtsCompanion.insert(
                mediaId: mediaId,
                mediaMode: mediaMode,
                title: title,
                synonyms: synonyms,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $LibraryFtsProcessedTableManager =
    ProcessedTableManager<
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
      PrefetchHooks Function()
    >;

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
  $LibraryFtsTableManager get libraryFts =>
      $LibraryFtsTableManager(_db, _db.libraryFts);
}
