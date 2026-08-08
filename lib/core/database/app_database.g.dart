// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $PigsTable extends Pigs with TableInfo<$PigsTable, Pig> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PigsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagMeta = const VerificationMeta('tag');
  @override
  late final GeneratedColumn<String> tag = GeneratedColumn<String>(
    'tag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    tag,
    displayName,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pigs';
  @override
  VerificationContext validateIntegrity(
    Insertable<Pig> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('tag')) {
      context.handle(
        _tagMeta,
        tag.isAcceptableOrUnknown(data['tag']!, _tagMeta),
      );
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Pig map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Pig(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      tag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag'],
      ),
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $PigsTable createAlias(String alias) {
    return $PigsTable(attachedDatabase, alias);
  }
}

class Pig extends DataClass implements Insertable<Pig> {
  final String id;
  final String? tag;
  final String? displayName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const Pig({
    required this.id,
    this.tag,
    this.displayName,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || tag != null) {
      map['tag'] = Variable<String>(tag);
    }
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  PigsCompanion toCompanion(bool nullToAbsent) {
    return PigsCompanion(
      id: Value(id),
      tag: tag == null && nullToAbsent ? const Value.absent() : Value(tag),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Pig.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Pig(
      id: serializer.fromJson<String>(json['id']),
      tag: serializer.fromJson<String?>(json['tag']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'tag': serializer.toJson<String?>(tag),
      'displayName': serializer.toJson<String?>(displayName),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  Pig copyWith({
    String? id,
    Value<String?> tag = const Value.absent(),
    Value<String?> displayName = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => Pig(
    id: id ?? this.id,
    tag: tag.present ? tag.value : this.tag,
    displayName: displayName.present ? displayName.value : this.displayName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  Pig copyWithCompanion(PigsCompanion data) {
    return Pig(
      id: data.id.present ? data.id.value : this.id,
      tag: data.tag.present ? data.tag.value : this.tag,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Pig(')
          ..write('id: $id, ')
          ..write('tag: $tag, ')
          ..write('displayName: $displayName, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, tag, displayName, createdAt, updatedAt, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Pig &&
          other.id == this.id &&
          other.tag == this.tag &&
          other.displayName == this.displayName &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class PigsCompanion extends UpdateCompanion<Pig> {
  final Value<String> id;
  final Value<String?> tag;
  final Value<String?> displayName;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const PigsCompanion({
    this.id = const Value.absent(),
    this.tag = const Value.absent(),
    this.displayName = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PigsCompanion.insert({
    required String id,
    this.tag = const Value.absent(),
    this.displayName = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<Pig> custom({
    Expression<String>? id,
    Expression<String>? tag,
    Expression<String>? displayName,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (tag != null) 'tag': tag,
      if (displayName != null) 'display_name': displayName,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PigsCompanion copyWith({
    Value<String>? id,
    Value<String?>? tag,
    Value<String?>? displayName,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return PigsCompanion(
      id: id ?? this.id,
      tag: tag ?? this.tag,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (tag.present) {
      map['tag'] = Variable<String>(tag.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PigsCompanion(')
          ..write('id: $id, ')
          ..write('tag: $tag, ')
          ..write('displayName: $displayName, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ScanRecordsTable extends ScanRecords
    with TableInfo<$ScanRecordsTable, ScanRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScanRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pigIdMeta = const VerificationMeta('pigId');
  @override
  late final GeneratedColumn<String> pigId = GeneratedColumn<String>(
    'pig_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pigs (id)',
    ),
  );
  static const VerificationMeta _goalMeta = const VerificationMeta('goal');
  @override
  late final GeneratedColumn<String> goal = GeneratedColumn<String>(
    'goal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(ScanStatuses.draft),
  );
  static const VerificationMeta _imagePathMeta = const VerificationMeta(
    'imagePath',
  );
  @override
  late final GeneratedColumn<String> imagePath = GeneratedColumn<String>(
    'image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failureCodeMeta = const VerificationMeta(
    'failureCode',
  );
  @override
  late final GeneratedColumn<String> failureCode = GeneratedColumn<String>(
    'failure_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failureMessageMeta = const VerificationMeta(
    'failureMessage',
  );
  @override
  late final GeneratedColumn<String> failureMessage = GeneratedColumn<String>(
    'failure_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _capturedAtMeta = const VerificationMeta(
    'capturedAt',
  );
  @override
  late final GeneratedColumn<DateTime> capturedAt = GeneratedColumn<DateTime>(
    'captured_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local'),
  );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  @override
  late final GeneratedColumn<String> remoteId = GeneratedColumn<String>(
    'remote_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    pigId,
    goal,
    status,
    imagePath,
    failureCode,
    failureMessage,
    notes,
    capturedAt,
    createdAt,
    updatedAt,
    deletedAt,
    syncState,
    remoteId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scan_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScanRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('pig_id')) {
      context.handle(
        _pigIdMeta,
        pigId.isAcceptableOrUnknown(data['pig_id']!, _pigIdMeta),
      );
    }
    if (data.containsKey('goal')) {
      context.handle(
        _goalMeta,
        goal.isAcceptableOrUnknown(data['goal']!, _goalMeta),
      );
    } else if (isInserting) {
      context.missing(_goalMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('image_path')) {
      context.handle(
        _imagePathMeta,
        imagePath.isAcceptableOrUnknown(data['image_path']!, _imagePathMeta),
      );
    }
    if (data.containsKey('failure_code')) {
      context.handle(
        _failureCodeMeta,
        failureCode.isAcceptableOrUnknown(
          data['failure_code']!,
          _failureCodeMeta,
        ),
      );
    }
    if (data.containsKey('failure_message')) {
      context.handle(
        _failureMessageMeta,
        failureMessage.isAcceptableOrUnknown(
          data['failure_message']!,
          _failureMessageMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('captured_at')) {
      context.handle(
        _capturedAtMeta,
        capturedAt.isAcceptableOrUnknown(data['captured_at']!, _capturedAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScanRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScanRecord(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      pigId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pig_id'],
      ),
      goal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}goal'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      imagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_path'],
      ),
      failureCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_code'],
      ),
      failureMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_message'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      capturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}captured_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
      remoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_id'],
      ),
    );
  }

  @override
  $ScanRecordsTable createAlias(String alias) {
    return $ScanRecordsTable(attachedDatabase, alias);
  }
}

class ScanRecord extends DataClass implements Insertable<ScanRecord> {
  final String id;
  final String? pigId;
  final String goal;
  final String status;
  final String? imagePath;
  final String? failureCode;
  final String? failureMessage;
  final String? notes;
  final DateTime? capturedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String syncState;
  final String? remoteId;
  const ScanRecord({
    required this.id,
    this.pigId,
    required this.goal,
    required this.status,
    this.imagePath,
    this.failureCode,
    this.failureMessage,
    this.notes,
    this.capturedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.syncState,
    this.remoteId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || pigId != null) {
      map['pig_id'] = Variable<String>(pigId);
    }
    map['goal'] = Variable<String>(goal);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || imagePath != null) {
      map['image_path'] = Variable<String>(imagePath);
    }
    if (!nullToAbsent || failureCode != null) {
      map['failure_code'] = Variable<String>(failureCode);
    }
    if (!nullToAbsent || failureMessage != null) {
      map['failure_message'] = Variable<String>(failureMessage);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || capturedAt != null) {
      map['captured_at'] = Variable<DateTime>(capturedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['sync_state'] = Variable<String>(syncState);
    if (!nullToAbsent || remoteId != null) {
      map['remote_id'] = Variable<String>(remoteId);
    }
    return map;
  }

  ScanRecordsCompanion toCompanion(bool nullToAbsent) {
    return ScanRecordsCompanion(
      id: Value(id),
      pigId: pigId == null && nullToAbsent
          ? const Value.absent()
          : Value(pigId),
      goal: Value(goal),
      status: Value(status),
      imagePath: imagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(imagePath),
      failureCode: failureCode == null && nullToAbsent
          ? const Value.absent()
          : Value(failureCode),
      failureMessage: failureMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(failureMessage),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      capturedAt: capturedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(capturedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncState: Value(syncState),
      remoteId: remoteId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteId),
    );
  }

  factory ScanRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScanRecord(
      id: serializer.fromJson<String>(json['id']),
      pigId: serializer.fromJson<String?>(json['pigId']),
      goal: serializer.fromJson<String>(json['goal']),
      status: serializer.fromJson<String>(json['status']),
      imagePath: serializer.fromJson<String?>(json['imagePath']),
      failureCode: serializer.fromJson<String?>(json['failureCode']),
      failureMessage: serializer.fromJson<String?>(json['failureMessage']),
      notes: serializer.fromJson<String?>(json['notes']),
      capturedAt: serializer.fromJson<DateTime?>(json['capturedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncState: serializer.fromJson<String>(json['syncState']),
      remoteId: serializer.fromJson<String?>(json['remoteId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'pigId': serializer.toJson<String?>(pigId),
      'goal': serializer.toJson<String>(goal),
      'status': serializer.toJson<String>(status),
      'imagePath': serializer.toJson<String?>(imagePath),
      'failureCode': serializer.toJson<String?>(failureCode),
      'failureMessage': serializer.toJson<String?>(failureMessage),
      'notes': serializer.toJson<String?>(notes),
      'capturedAt': serializer.toJson<DateTime?>(capturedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncState': serializer.toJson<String>(syncState),
      'remoteId': serializer.toJson<String?>(remoteId),
    };
  }

  ScanRecord copyWith({
    String? id,
    Value<String?> pigId = const Value.absent(),
    String? goal,
    String? status,
    Value<String?> imagePath = const Value.absent(),
    Value<String?> failureCode = const Value.absent(),
    Value<String?> failureMessage = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<DateTime?> capturedAt = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? syncState,
    Value<String?> remoteId = const Value.absent(),
  }) => ScanRecord(
    id: id ?? this.id,
    pigId: pigId.present ? pigId.value : this.pigId,
    goal: goal ?? this.goal,
    status: status ?? this.status,
    imagePath: imagePath.present ? imagePath.value : this.imagePath,
    failureCode: failureCode.present ? failureCode.value : this.failureCode,
    failureMessage: failureMessage.present
        ? failureMessage.value
        : this.failureMessage,
    notes: notes.present ? notes.value : this.notes,
    capturedAt: capturedAt.present ? capturedAt.value : this.capturedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncState: syncState ?? this.syncState,
    remoteId: remoteId.present ? remoteId.value : this.remoteId,
  );
  ScanRecord copyWithCompanion(ScanRecordsCompanion data) {
    return ScanRecord(
      id: data.id.present ? data.id.value : this.id,
      pigId: data.pigId.present ? data.pigId.value : this.pigId,
      goal: data.goal.present ? data.goal.value : this.goal,
      status: data.status.present ? data.status.value : this.status,
      imagePath: data.imagePath.present ? data.imagePath.value : this.imagePath,
      failureCode: data.failureCode.present
          ? data.failureCode.value
          : this.failureCode,
      failureMessage: data.failureMessage.present
          ? data.failureMessage.value
          : this.failureMessage,
      notes: data.notes.present ? data.notes.value : this.notes,
      capturedAt: data.capturedAt.present
          ? data.capturedAt.value
          : this.capturedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScanRecord(')
          ..write('id: $id, ')
          ..write('pigId: $pigId, ')
          ..write('goal: $goal, ')
          ..write('status: $status, ')
          ..write('imagePath: $imagePath, ')
          ..write('failureCode: $failureCode, ')
          ..write('failureMessage: $failureMessage, ')
          ..write('notes: $notes, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncState: $syncState, ')
          ..write('remoteId: $remoteId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    pigId,
    goal,
    status,
    imagePath,
    failureCode,
    failureMessage,
    notes,
    capturedAt,
    createdAt,
    updatedAt,
    deletedAt,
    syncState,
    remoteId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScanRecord &&
          other.id == this.id &&
          other.pigId == this.pigId &&
          other.goal == this.goal &&
          other.status == this.status &&
          other.imagePath == this.imagePath &&
          other.failureCode == this.failureCode &&
          other.failureMessage == this.failureMessage &&
          other.notes == this.notes &&
          other.capturedAt == this.capturedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncState == this.syncState &&
          other.remoteId == this.remoteId);
}

class ScanRecordsCompanion extends UpdateCompanion<ScanRecord> {
  final Value<String> id;
  final Value<String?> pigId;
  final Value<String> goal;
  final Value<String> status;
  final Value<String?> imagePath;
  final Value<String?> failureCode;
  final Value<String?> failureMessage;
  final Value<String?> notes;
  final Value<DateTime?> capturedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String> syncState;
  final Value<String?> remoteId;
  final Value<int> rowid;
  const ScanRecordsCompanion({
    this.id = const Value.absent(),
    this.pigId = const Value.absent(),
    this.goal = const Value.absent(),
    this.status = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.failureCode = const Value.absent(),
    this.failureMessage = const Value.absent(),
    this.notes = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncState = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScanRecordsCompanion.insert({
    required String id,
    this.pigId = const Value.absent(),
    required String goal,
    this.status = const Value.absent(),
    this.imagePath = const Value.absent(),
    this.failureCode = const Value.absent(),
    this.failureMessage = const Value.absent(),
    this.notes = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncState = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       goal = Value(goal);
  static Insertable<ScanRecord> custom({
    Expression<String>? id,
    Expression<String>? pigId,
    Expression<String>? goal,
    Expression<String>? status,
    Expression<String>? imagePath,
    Expression<String>? failureCode,
    Expression<String>? failureMessage,
    Expression<String>? notes,
    Expression<DateTime>? capturedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncState,
    Expression<String>? remoteId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (pigId != null) 'pig_id': pigId,
      if (goal != null) 'goal': goal,
      if (status != null) 'status': status,
      if (imagePath != null) 'image_path': imagePath,
      if (failureCode != null) 'failure_code': failureCode,
      if (failureMessage != null) 'failure_message': failureMessage,
      if (notes != null) 'notes': notes,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncState != null) 'sync_state': syncState,
      if (remoteId != null) 'remote_id': remoteId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScanRecordsCompanion copyWith({
    Value<String>? id,
    Value<String?>? pigId,
    Value<String>? goal,
    Value<String>? status,
    Value<String?>? imagePath,
    Value<String?>? failureCode,
    Value<String?>? failureMessage,
    Value<String?>? notes,
    Value<DateTime?>? capturedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String>? syncState,
    Value<String?>? remoteId,
    Value<int>? rowid,
  }) {
    return ScanRecordsCompanion(
      id: id ?? this.id,
      pigId: pigId ?? this.pigId,
      goal: goal ?? this.goal,
      status: status ?? this.status,
      imagePath: imagePath ?? this.imagePath,
      failureCode: failureCode ?? this.failureCode,
      failureMessage: failureMessage ?? this.failureMessage,
      notes: notes ?? this.notes,
      capturedAt: capturedAt ?? this.capturedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncState: syncState ?? this.syncState,
      remoteId: remoteId ?? this.remoteId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (pigId.present) {
      map['pig_id'] = Variable<String>(pigId.value);
    }
    if (goal.present) {
      map['goal'] = Variable<String>(goal.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (imagePath.present) {
      map['image_path'] = Variable<String>(imagePath.value);
    }
    if (failureCode.present) {
      map['failure_code'] = Variable<String>(failureCode.value);
    }
    if (failureMessage.present) {
      map['failure_message'] = Variable<String>(failureMessage.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<DateTime>(capturedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<String>(remoteId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScanRecordsCompanion(')
          ..write('id: $id, ')
          ..write('pigId: $pigId, ')
          ..write('goal: $goal, ')
          ..write('status: $status, ')
          ..write('imagePath: $imagePath, ')
          ..write('failureCode: $failureCode, ')
          ..write('failureMessage: $failureMessage, ')
          ..write('notes: $notes, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncState: $syncState, ')
          ..write('remoteId: $remoteId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReferenceAnnotationsTable extends ReferenceAnnotations
    with TableInfo<$ReferenceAnnotationsTable, ReferenceAnnotation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReferenceAnnotationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scanIdMeta = const VerificationMeta('scanId');
  @override
  late final GeneratedColumn<String> scanId = GeneratedColumn<String>(
    'scan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES scan_records (id)',
    ),
  );
  static const VerificationMeta _objectTypeMeta = const VerificationMeta(
    'objectType',
  );
  @override
  late final GeneratedColumn<String> objectType = GeneratedColumn<String>(
    'object_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _objectNameMeta = const VerificationMeta(
    'objectName',
  );
  @override
  late final GeneratedColumn<String> objectName = GeneratedColumn<String>(
    'object_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lengthCmMeta = const VerificationMeta(
    'lengthCm',
  );
  @override
  late final GeneratedColumn<double> lengthCm = GeneratedColumn<double>(
    'length_cm',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startXMeta = const VerificationMeta('startX');
  @override
  late final GeneratedColumn<double> startX = GeneratedColumn<double>(
    'start_x',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startYMeta = const VerificationMeta('startY');
  @override
  late final GeneratedColumn<double> startY = GeneratedColumn<double>(
    'start_y',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endXMeta = const VerificationMeta('endX');
  @override
  late final GeneratedColumn<double> endX = GeneratedColumn<double>(
    'end_x',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endYMeta = const VerificationMeta('endY');
  @override
  late final GeneratedColumn<double> endY = GeneratedColumn<double>(
    'end_y',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pixelLengthMeta = const VerificationMeta(
    'pixelLength',
  );
  @override
  late final GeneratedColumn<double> pixelLength = GeneratedColumn<double>(
    'pixel_length',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cmPerPixelMeta = const VerificationMeta(
    'cmPerPixel',
  );
  @override
  late final GeneratedColumn<double> cmPerPixel = GeneratedColumn<double>(
    'cm_per_pixel',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('manual'),
  );
  static const VerificationMeta _detectorConfidenceMeta =
      const VerificationMeta('detectorConfidence');
  @override
  late final GeneratedColumn<double> detectorConfidence =
      GeneratedColumn<double>(
        'detector_confidence',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _userConfirmedMeta = const VerificationMeta(
    'userConfirmed',
  );
  @override
  late final GeneratedColumn<bool> userConfirmed = GeneratedColumn<bool>(
    'user_confirmed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("user_confirmed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sameFloorPlaneConfirmedMeta =
      const VerificationMeta('sameFloorPlaneConfirmed');
  @override
  late final GeneratedColumn<bool> sameFloorPlaneConfirmed =
      GeneratedColumn<bool>(
        'same_floor_plane_confirmed',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("same_floor_plane_confirmed" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    scanId,
    objectType,
    objectName,
    lengthCm,
    startX,
    startY,
    endX,
    endY,
    pixelLength,
    cmPerPixel,
    source,
    detectorConfidence,
    userConfirmed,
    sameFloorPlaneConfirmed,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reference_annotations';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReferenceAnnotation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scan_id')) {
      context.handle(
        _scanIdMeta,
        scanId.isAcceptableOrUnknown(data['scan_id']!, _scanIdMeta),
      );
    } else if (isInserting) {
      context.missing(_scanIdMeta);
    }
    if (data.containsKey('object_type')) {
      context.handle(
        _objectTypeMeta,
        objectType.isAcceptableOrUnknown(data['object_type']!, _objectTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_objectTypeMeta);
    }
    if (data.containsKey('object_name')) {
      context.handle(
        _objectNameMeta,
        objectName.isAcceptableOrUnknown(data['object_name']!, _objectNameMeta),
      );
    } else if (isInserting) {
      context.missing(_objectNameMeta);
    }
    if (data.containsKey('length_cm')) {
      context.handle(
        _lengthCmMeta,
        lengthCm.isAcceptableOrUnknown(data['length_cm']!, _lengthCmMeta),
      );
    } else if (isInserting) {
      context.missing(_lengthCmMeta);
    }
    if (data.containsKey('start_x')) {
      context.handle(
        _startXMeta,
        startX.isAcceptableOrUnknown(data['start_x']!, _startXMeta),
      );
    }
    if (data.containsKey('start_y')) {
      context.handle(
        _startYMeta,
        startY.isAcceptableOrUnknown(data['start_y']!, _startYMeta),
      );
    }
    if (data.containsKey('end_x')) {
      context.handle(
        _endXMeta,
        endX.isAcceptableOrUnknown(data['end_x']!, _endXMeta),
      );
    }
    if (data.containsKey('end_y')) {
      context.handle(
        _endYMeta,
        endY.isAcceptableOrUnknown(data['end_y']!, _endYMeta),
      );
    }
    if (data.containsKey('pixel_length')) {
      context.handle(
        _pixelLengthMeta,
        pixelLength.isAcceptableOrUnknown(
          data['pixel_length']!,
          _pixelLengthMeta,
        ),
      );
    }
    if (data.containsKey('cm_per_pixel')) {
      context.handle(
        _cmPerPixelMeta,
        cmPerPixel.isAcceptableOrUnknown(
          data['cm_per_pixel']!,
          _cmPerPixelMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('detector_confidence')) {
      context.handle(
        _detectorConfidenceMeta,
        detectorConfidence.isAcceptableOrUnknown(
          data['detector_confidence']!,
          _detectorConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('user_confirmed')) {
      context.handle(
        _userConfirmedMeta,
        userConfirmed.isAcceptableOrUnknown(
          data['user_confirmed']!,
          _userConfirmedMeta,
        ),
      );
    }
    if (data.containsKey('same_floor_plane_confirmed')) {
      context.handle(
        _sameFloorPlaneConfirmedMeta,
        sameFloorPlaneConfirmed.isAcceptableOrUnknown(
          data['same_floor_plane_confirmed']!,
          _sameFloorPlaneConfirmedMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scanId};
  @override
  ReferenceAnnotation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReferenceAnnotation(
      scanId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scan_id'],
      )!,
      objectType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}object_type'],
      )!,
      objectName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}object_name'],
      )!,
      lengthCm: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}length_cm'],
      )!,
      startX: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}start_x'],
      ),
      startY: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}start_y'],
      ),
      endX: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}end_x'],
      ),
      endY: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}end_y'],
      ),
      pixelLength: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pixel_length'],
      ),
      cmPerPixel: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cm_per_pixel'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      detectorConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}detector_confidence'],
      ),
      userConfirmed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}user_confirmed'],
      )!,
      sameFloorPlaneConfirmed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}same_floor_plane_confirmed'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReferenceAnnotationsTable createAlias(String alias) {
    return $ReferenceAnnotationsTable(attachedDatabase, alias);
  }
}

class ReferenceAnnotation extends DataClass
    implements Insertable<ReferenceAnnotation> {
  final String scanId;
  final String objectType;
  final String objectName;
  final double lengthCm;
  final double? startX;
  final double? startY;
  final double? endX;
  final double? endY;
  final double? pixelLength;
  final double? cmPerPixel;
  final String source;
  final double? detectorConfidence;
  final bool userConfirmed;
  final bool sameFloorPlaneConfirmed;
  final DateTime updatedAt;
  const ReferenceAnnotation({
    required this.scanId,
    required this.objectType,
    required this.objectName,
    required this.lengthCm,
    this.startX,
    this.startY,
    this.endX,
    this.endY,
    this.pixelLength,
    this.cmPerPixel,
    required this.source,
    this.detectorConfidence,
    required this.userConfirmed,
    required this.sameFloorPlaneConfirmed,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scan_id'] = Variable<String>(scanId);
    map['object_type'] = Variable<String>(objectType);
    map['object_name'] = Variable<String>(objectName);
    map['length_cm'] = Variable<double>(lengthCm);
    if (!nullToAbsent || startX != null) {
      map['start_x'] = Variable<double>(startX);
    }
    if (!nullToAbsent || startY != null) {
      map['start_y'] = Variable<double>(startY);
    }
    if (!nullToAbsent || endX != null) {
      map['end_x'] = Variable<double>(endX);
    }
    if (!nullToAbsent || endY != null) {
      map['end_y'] = Variable<double>(endY);
    }
    if (!nullToAbsent || pixelLength != null) {
      map['pixel_length'] = Variable<double>(pixelLength);
    }
    if (!nullToAbsent || cmPerPixel != null) {
      map['cm_per_pixel'] = Variable<double>(cmPerPixel);
    }
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || detectorConfidence != null) {
      map['detector_confidence'] = Variable<double>(detectorConfidence);
    }
    map['user_confirmed'] = Variable<bool>(userConfirmed);
    map['same_floor_plane_confirmed'] = Variable<bool>(sameFloorPlaneConfirmed);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ReferenceAnnotationsCompanion toCompanion(bool nullToAbsent) {
    return ReferenceAnnotationsCompanion(
      scanId: Value(scanId),
      objectType: Value(objectType),
      objectName: Value(objectName),
      lengthCm: Value(lengthCm),
      startX: startX == null && nullToAbsent
          ? const Value.absent()
          : Value(startX),
      startY: startY == null && nullToAbsent
          ? const Value.absent()
          : Value(startY),
      endX: endX == null && nullToAbsent ? const Value.absent() : Value(endX),
      endY: endY == null && nullToAbsent ? const Value.absent() : Value(endY),
      pixelLength: pixelLength == null && nullToAbsent
          ? const Value.absent()
          : Value(pixelLength),
      cmPerPixel: cmPerPixel == null && nullToAbsent
          ? const Value.absent()
          : Value(cmPerPixel),
      source: Value(source),
      detectorConfidence: detectorConfidence == null && nullToAbsent
          ? const Value.absent()
          : Value(detectorConfidence),
      userConfirmed: Value(userConfirmed),
      sameFloorPlaneConfirmed: Value(sameFloorPlaneConfirmed),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReferenceAnnotation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReferenceAnnotation(
      scanId: serializer.fromJson<String>(json['scanId']),
      objectType: serializer.fromJson<String>(json['objectType']),
      objectName: serializer.fromJson<String>(json['objectName']),
      lengthCm: serializer.fromJson<double>(json['lengthCm']),
      startX: serializer.fromJson<double?>(json['startX']),
      startY: serializer.fromJson<double?>(json['startY']),
      endX: serializer.fromJson<double?>(json['endX']),
      endY: serializer.fromJson<double?>(json['endY']),
      pixelLength: serializer.fromJson<double?>(json['pixelLength']),
      cmPerPixel: serializer.fromJson<double?>(json['cmPerPixel']),
      source: serializer.fromJson<String>(json['source']),
      detectorConfidence: serializer.fromJson<double?>(
        json['detectorConfidence'],
      ),
      userConfirmed: serializer.fromJson<bool>(json['userConfirmed']),
      sameFloorPlaneConfirmed: serializer.fromJson<bool>(
        json['sameFloorPlaneConfirmed'],
      ),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scanId': serializer.toJson<String>(scanId),
      'objectType': serializer.toJson<String>(objectType),
      'objectName': serializer.toJson<String>(objectName),
      'lengthCm': serializer.toJson<double>(lengthCm),
      'startX': serializer.toJson<double?>(startX),
      'startY': serializer.toJson<double?>(startY),
      'endX': serializer.toJson<double?>(endX),
      'endY': serializer.toJson<double?>(endY),
      'pixelLength': serializer.toJson<double?>(pixelLength),
      'cmPerPixel': serializer.toJson<double?>(cmPerPixel),
      'source': serializer.toJson<String>(source),
      'detectorConfidence': serializer.toJson<double?>(detectorConfidence),
      'userConfirmed': serializer.toJson<bool>(userConfirmed),
      'sameFloorPlaneConfirmed': serializer.toJson<bool>(
        sameFloorPlaneConfirmed,
      ),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ReferenceAnnotation copyWith({
    String? scanId,
    String? objectType,
    String? objectName,
    double? lengthCm,
    Value<double?> startX = const Value.absent(),
    Value<double?> startY = const Value.absent(),
    Value<double?> endX = const Value.absent(),
    Value<double?> endY = const Value.absent(),
    Value<double?> pixelLength = const Value.absent(),
    Value<double?> cmPerPixel = const Value.absent(),
    String? source,
    Value<double?> detectorConfidence = const Value.absent(),
    bool? userConfirmed,
    bool? sameFloorPlaneConfirmed,
    DateTime? updatedAt,
  }) => ReferenceAnnotation(
    scanId: scanId ?? this.scanId,
    objectType: objectType ?? this.objectType,
    objectName: objectName ?? this.objectName,
    lengthCm: lengthCm ?? this.lengthCm,
    startX: startX.present ? startX.value : this.startX,
    startY: startY.present ? startY.value : this.startY,
    endX: endX.present ? endX.value : this.endX,
    endY: endY.present ? endY.value : this.endY,
    pixelLength: pixelLength.present ? pixelLength.value : this.pixelLength,
    cmPerPixel: cmPerPixel.present ? cmPerPixel.value : this.cmPerPixel,
    source: source ?? this.source,
    detectorConfidence: detectorConfidence.present
        ? detectorConfidence.value
        : this.detectorConfidence,
    userConfirmed: userConfirmed ?? this.userConfirmed,
    sameFloorPlaneConfirmed:
        sameFloorPlaneConfirmed ?? this.sameFloorPlaneConfirmed,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReferenceAnnotation copyWithCompanion(ReferenceAnnotationsCompanion data) {
    return ReferenceAnnotation(
      scanId: data.scanId.present ? data.scanId.value : this.scanId,
      objectType: data.objectType.present
          ? data.objectType.value
          : this.objectType,
      objectName: data.objectName.present
          ? data.objectName.value
          : this.objectName,
      lengthCm: data.lengthCm.present ? data.lengthCm.value : this.lengthCm,
      startX: data.startX.present ? data.startX.value : this.startX,
      startY: data.startY.present ? data.startY.value : this.startY,
      endX: data.endX.present ? data.endX.value : this.endX,
      endY: data.endY.present ? data.endY.value : this.endY,
      pixelLength: data.pixelLength.present
          ? data.pixelLength.value
          : this.pixelLength,
      cmPerPixel: data.cmPerPixel.present
          ? data.cmPerPixel.value
          : this.cmPerPixel,
      source: data.source.present ? data.source.value : this.source,
      detectorConfidence: data.detectorConfidence.present
          ? data.detectorConfidence.value
          : this.detectorConfidence,
      userConfirmed: data.userConfirmed.present
          ? data.userConfirmed.value
          : this.userConfirmed,
      sameFloorPlaneConfirmed: data.sameFloorPlaneConfirmed.present
          ? data.sameFloorPlaneConfirmed.value
          : this.sameFloorPlaneConfirmed,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReferenceAnnotation(')
          ..write('scanId: $scanId, ')
          ..write('objectType: $objectType, ')
          ..write('objectName: $objectName, ')
          ..write('lengthCm: $lengthCm, ')
          ..write('startX: $startX, ')
          ..write('startY: $startY, ')
          ..write('endX: $endX, ')
          ..write('endY: $endY, ')
          ..write('pixelLength: $pixelLength, ')
          ..write('cmPerPixel: $cmPerPixel, ')
          ..write('source: $source, ')
          ..write('detectorConfidence: $detectorConfidence, ')
          ..write('userConfirmed: $userConfirmed, ')
          ..write('sameFloorPlaneConfirmed: $sameFloorPlaneConfirmed, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    scanId,
    objectType,
    objectName,
    lengthCm,
    startX,
    startY,
    endX,
    endY,
    pixelLength,
    cmPerPixel,
    source,
    detectorConfidence,
    userConfirmed,
    sameFloorPlaneConfirmed,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReferenceAnnotation &&
          other.scanId == this.scanId &&
          other.objectType == this.objectType &&
          other.objectName == this.objectName &&
          other.lengthCm == this.lengthCm &&
          other.startX == this.startX &&
          other.startY == this.startY &&
          other.endX == this.endX &&
          other.endY == this.endY &&
          other.pixelLength == this.pixelLength &&
          other.cmPerPixel == this.cmPerPixel &&
          other.source == this.source &&
          other.detectorConfidence == this.detectorConfidence &&
          other.userConfirmed == this.userConfirmed &&
          other.sameFloorPlaneConfirmed == this.sameFloorPlaneConfirmed &&
          other.updatedAt == this.updatedAt);
}

class ReferenceAnnotationsCompanion
    extends UpdateCompanion<ReferenceAnnotation> {
  final Value<String> scanId;
  final Value<String> objectType;
  final Value<String> objectName;
  final Value<double> lengthCm;
  final Value<double?> startX;
  final Value<double?> startY;
  final Value<double?> endX;
  final Value<double?> endY;
  final Value<double?> pixelLength;
  final Value<double?> cmPerPixel;
  final Value<String> source;
  final Value<double?> detectorConfidence;
  final Value<bool> userConfirmed;
  final Value<bool> sameFloorPlaneConfirmed;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ReferenceAnnotationsCompanion({
    this.scanId = const Value.absent(),
    this.objectType = const Value.absent(),
    this.objectName = const Value.absent(),
    this.lengthCm = const Value.absent(),
    this.startX = const Value.absent(),
    this.startY = const Value.absent(),
    this.endX = const Value.absent(),
    this.endY = const Value.absent(),
    this.pixelLength = const Value.absent(),
    this.cmPerPixel = const Value.absent(),
    this.source = const Value.absent(),
    this.detectorConfidence = const Value.absent(),
    this.userConfirmed = const Value.absent(),
    this.sameFloorPlaneConfirmed = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReferenceAnnotationsCompanion.insert({
    required String scanId,
    required String objectType,
    required String objectName,
    required double lengthCm,
    this.startX = const Value.absent(),
    this.startY = const Value.absent(),
    this.endX = const Value.absent(),
    this.endY = const Value.absent(),
    this.pixelLength = const Value.absent(),
    this.cmPerPixel = const Value.absent(),
    this.source = const Value.absent(),
    this.detectorConfidence = const Value.absent(),
    this.userConfirmed = const Value.absent(),
    this.sameFloorPlaneConfirmed = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : scanId = Value(scanId),
       objectType = Value(objectType),
       objectName = Value(objectName),
       lengthCm = Value(lengthCm);
  static Insertable<ReferenceAnnotation> custom({
    Expression<String>? scanId,
    Expression<String>? objectType,
    Expression<String>? objectName,
    Expression<double>? lengthCm,
    Expression<double>? startX,
    Expression<double>? startY,
    Expression<double>? endX,
    Expression<double>? endY,
    Expression<double>? pixelLength,
    Expression<double>? cmPerPixel,
    Expression<String>? source,
    Expression<double>? detectorConfidence,
    Expression<bool>? userConfirmed,
    Expression<bool>? sameFloorPlaneConfirmed,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scanId != null) 'scan_id': scanId,
      if (objectType != null) 'object_type': objectType,
      if (objectName != null) 'object_name': objectName,
      if (lengthCm != null) 'length_cm': lengthCm,
      if (startX != null) 'start_x': startX,
      if (startY != null) 'start_y': startY,
      if (endX != null) 'end_x': endX,
      if (endY != null) 'end_y': endY,
      if (pixelLength != null) 'pixel_length': pixelLength,
      if (cmPerPixel != null) 'cm_per_pixel': cmPerPixel,
      if (source != null) 'source': source,
      if (detectorConfidence != null) 'detector_confidence': detectorConfidence,
      if (userConfirmed != null) 'user_confirmed': userConfirmed,
      if (sameFloorPlaneConfirmed != null)
        'same_floor_plane_confirmed': sameFloorPlaneConfirmed,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReferenceAnnotationsCompanion copyWith({
    Value<String>? scanId,
    Value<String>? objectType,
    Value<String>? objectName,
    Value<double>? lengthCm,
    Value<double?>? startX,
    Value<double?>? startY,
    Value<double?>? endX,
    Value<double?>? endY,
    Value<double?>? pixelLength,
    Value<double?>? cmPerPixel,
    Value<String>? source,
    Value<double?>? detectorConfidence,
    Value<bool>? userConfirmed,
    Value<bool>? sameFloorPlaneConfirmed,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReferenceAnnotationsCompanion(
      scanId: scanId ?? this.scanId,
      objectType: objectType ?? this.objectType,
      objectName: objectName ?? this.objectName,
      lengthCm: lengthCm ?? this.lengthCm,
      startX: startX ?? this.startX,
      startY: startY ?? this.startY,
      endX: endX ?? this.endX,
      endY: endY ?? this.endY,
      pixelLength: pixelLength ?? this.pixelLength,
      cmPerPixel: cmPerPixel ?? this.cmPerPixel,
      source: source ?? this.source,
      detectorConfidence: detectorConfidence ?? this.detectorConfidence,
      userConfirmed: userConfirmed ?? this.userConfirmed,
      sameFloorPlaneConfirmed:
          sameFloorPlaneConfirmed ?? this.sameFloorPlaneConfirmed,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scanId.present) {
      map['scan_id'] = Variable<String>(scanId.value);
    }
    if (objectType.present) {
      map['object_type'] = Variable<String>(objectType.value);
    }
    if (objectName.present) {
      map['object_name'] = Variable<String>(objectName.value);
    }
    if (lengthCm.present) {
      map['length_cm'] = Variable<double>(lengthCm.value);
    }
    if (startX.present) {
      map['start_x'] = Variable<double>(startX.value);
    }
    if (startY.present) {
      map['start_y'] = Variable<double>(startY.value);
    }
    if (endX.present) {
      map['end_x'] = Variable<double>(endX.value);
    }
    if (endY.present) {
      map['end_y'] = Variable<double>(endY.value);
    }
    if (pixelLength.present) {
      map['pixel_length'] = Variable<double>(pixelLength.value);
    }
    if (cmPerPixel.present) {
      map['cm_per_pixel'] = Variable<double>(cmPerPixel.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (detectorConfidence.present) {
      map['detector_confidence'] = Variable<double>(detectorConfidence.value);
    }
    if (userConfirmed.present) {
      map['user_confirmed'] = Variable<bool>(userConfirmed.value);
    }
    if (sameFloorPlaneConfirmed.present) {
      map['same_floor_plane_confirmed'] = Variable<bool>(
        sameFloorPlaneConfirmed.value,
      );
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReferenceAnnotationsCompanion(')
          ..write('scanId: $scanId, ')
          ..write('objectType: $objectType, ')
          ..write('objectName: $objectName, ')
          ..write('lengthCm: $lengthCm, ')
          ..write('startX: $startX, ')
          ..write('startY: $startY, ')
          ..write('endX: $endX, ')
          ..write('endY: $endY, ')
          ..write('pixelLength: $pixelLength, ')
          ..write('cmPerPixel: $cmPerPixel, ')
          ..write('source: $source, ')
          ..write('detectorConfidence: $detectorConfidence, ')
          ..write('userConfirmed: $userConfirmed, ')
          ..write('sameFloorPlaneConfirmed: $sameFloorPlaneConfirmed, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WeightResultsTable extends WeightResults
    with TableInfo<$WeightResultsTable, WeightResult> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WeightResultsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scanIdMeta = const VerificationMeta('scanId');
  @override
  late final GeneratedColumn<String> scanId = GeneratedColumn<String>(
    'scan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES scan_records (id)',
    ),
  );
  static const VerificationMeta _eligibleMeta = const VerificationMeta(
    'eligible',
  );
  @override
  late final GeneratedColumn<bool> eligible = GeneratedColumn<bool>(
    'eligible',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("eligible" IN (0, 1))',
    ),
  );
  static const VerificationMeta _valueKgMeta = const VerificationMeta(
    'valueKg',
  );
  @override
  late final GeneratedColumn<double> valueKg = GeneratedColumn<double>(
    'value_kg',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _referenceLengthCmMeta = const VerificationMeta(
    'referenceLengthCm',
  );
  @override
  late final GeneratedColumn<double> referenceLengthCm =
      GeneratedColumn<double>(
        'reference_length_cm',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _referencePixelLengthMeta =
      const VerificationMeta('referencePixelLength');
  @override
  late final GeneratedColumn<double> referencePixelLength =
      GeneratedColumn<double>(
        'reference_pixel_length',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _cmPerPixelMeta = const VerificationMeta(
    'cmPerPixel',
  );
  @override
  late final GeneratedColumn<double> cmPerPixel = GeneratedColumn<double>(
    'cm_per_pixel',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _featureRaMeta = const VerificationMeta(
    'featureRa',
  );
  @override
  late final GeneratedColumn<double> featureRa = GeneratedColumn<double>(
    'feature_ra',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _featureLcMeta = const VerificationMeta(
    'featureLc',
  );
  @override
  late final GeneratedColumn<double> featureLc = GeneratedColumn<double>(
    'feature_lc',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _featureBlMeta = const VerificationMeta(
    'featureBl',
  );
  @override
  late final GeneratedColumn<double> featureBl = GeneratedColumn<double>(
    'feature_bl',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _featureBwMeta = const VerificationMeta(
    'featureBw',
  );
  @override
  late final GeneratedColumn<double> featureBw = GeneratedColumn<double>(
    'feature_bw',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _featureEMeta = const VerificationMeta(
    'featureE',
  );
  @override
  late final GeneratedColumn<double> featureE = GeneratedColumn<double>(
    'feature_e',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _failureReasonMeta = const VerificationMeta(
    'failureReason',
  );
  @override
  late final GeneratedColumn<String> failureReason = GeneratedColumn<String>(
    'failure_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelVersionMeta = const VerificationMeta(
    'modelVersion',
  );
  @override
  late final GeneratedColumn<String> modelVersion = GeneratedColumn<String>(
    'model_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _preprocessingVersionMeta =
      const VerificationMeta('preprocessingVersion');
  @override
  late final GeneratedColumn<String> preprocessingVersion =
      GeneratedColumn<String>(
        'preprocessing_version',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _thresholdVersionMeta = const VerificationMeta(
    'thresholdVersion',
  );
  @override
  late final GeneratedColumn<String> thresholdVersion = GeneratedColumn<String>(
    'threshold_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    scanId,
    eligible,
    valueKg,
    referenceLengthCm,
    referencePixelLength,
    cmPerPixel,
    featureRa,
    featureLc,
    featureBl,
    featureBw,
    featureE,
    failureReason,
    modelVersion,
    preprocessingVersion,
    thresholdVersion,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'weight_results';
  @override
  VerificationContext validateIntegrity(
    Insertable<WeightResult> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scan_id')) {
      context.handle(
        _scanIdMeta,
        scanId.isAcceptableOrUnknown(data['scan_id']!, _scanIdMeta),
      );
    } else if (isInserting) {
      context.missing(_scanIdMeta);
    }
    if (data.containsKey('eligible')) {
      context.handle(
        _eligibleMeta,
        eligible.isAcceptableOrUnknown(data['eligible']!, _eligibleMeta),
      );
    } else if (isInserting) {
      context.missing(_eligibleMeta);
    }
    if (data.containsKey('value_kg')) {
      context.handle(
        _valueKgMeta,
        valueKg.isAcceptableOrUnknown(data['value_kg']!, _valueKgMeta),
      );
    }
    if (data.containsKey('reference_length_cm')) {
      context.handle(
        _referenceLengthCmMeta,
        referenceLengthCm.isAcceptableOrUnknown(
          data['reference_length_cm']!,
          _referenceLengthCmMeta,
        ),
      );
    }
    if (data.containsKey('reference_pixel_length')) {
      context.handle(
        _referencePixelLengthMeta,
        referencePixelLength.isAcceptableOrUnknown(
          data['reference_pixel_length']!,
          _referencePixelLengthMeta,
        ),
      );
    }
    if (data.containsKey('cm_per_pixel')) {
      context.handle(
        _cmPerPixelMeta,
        cmPerPixel.isAcceptableOrUnknown(
          data['cm_per_pixel']!,
          _cmPerPixelMeta,
        ),
      );
    }
    if (data.containsKey('feature_ra')) {
      context.handle(
        _featureRaMeta,
        featureRa.isAcceptableOrUnknown(data['feature_ra']!, _featureRaMeta),
      );
    }
    if (data.containsKey('feature_lc')) {
      context.handle(
        _featureLcMeta,
        featureLc.isAcceptableOrUnknown(data['feature_lc']!, _featureLcMeta),
      );
    }
    if (data.containsKey('feature_bl')) {
      context.handle(
        _featureBlMeta,
        featureBl.isAcceptableOrUnknown(data['feature_bl']!, _featureBlMeta),
      );
    }
    if (data.containsKey('feature_bw')) {
      context.handle(
        _featureBwMeta,
        featureBw.isAcceptableOrUnknown(data['feature_bw']!, _featureBwMeta),
      );
    }
    if (data.containsKey('feature_e')) {
      context.handle(
        _featureEMeta,
        featureE.isAcceptableOrUnknown(data['feature_e']!, _featureEMeta),
      );
    }
    if (data.containsKey('failure_reason')) {
      context.handle(
        _failureReasonMeta,
        failureReason.isAcceptableOrUnknown(
          data['failure_reason']!,
          _failureReasonMeta,
        ),
      );
    }
    if (data.containsKey('model_version')) {
      context.handle(
        _modelVersionMeta,
        modelVersion.isAcceptableOrUnknown(
          data['model_version']!,
          _modelVersionMeta,
        ),
      );
    }
    if (data.containsKey('preprocessing_version')) {
      context.handle(
        _preprocessingVersionMeta,
        preprocessingVersion.isAcceptableOrUnknown(
          data['preprocessing_version']!,
          _preprocessingVersionMeta,
        ),
      );
    }
    if (data.containsKey('threshold_version')) {
      context.handle(
        _thresholdVersionMeta,
        thresholdVersion.isAcceptableOrUnknown(
          data['threshold_version']!,
          _thresholdVersionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scanId};
  @override
  WeightResult map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WeightResult(
      scanId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scan_id'],
      )!,
      eligible: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}eligible'],
      )!,
      valueKg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}value_kg'],
      ),
      referenceLengthCm: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}reference_length_cm'],
      ),
      referencePixelLength: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}reference_pixel_length'],
      ),
      cmPerPixel: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cm_per_pixel'],
      ),
      featureRa: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}feature_ra'],
      ),
      featureLc: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}feature_lc'],
      ),
      featureBl: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}feature_bl'],
      ),
      featureBw: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}feature_bw'],
      ),
      featureE: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}feature_e'],
      ),
      failureReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_reason'],
      ),
      modelVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_version'],
      ),
      preprocessingVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preprocessing_version'],
      ),
      thresholdVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}threshold_version'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $WeightResultsTable createAlias(String alias) {
    return $WeightResultsTable(attachedDatabase, alias);
  }
}

class WeightResult extends DataClass implements Insertable<WeightResult> {
  final String scanId;
  final bool eligible;
  final double? valueKg;
  final double? referenceLengthCm;
  final double? referencePixelLength;
  final double? cmPerPixel;
  final double? featureRa;
  final double? featureLc;
  final double? featureBl;
  final double? featureBw;
  final double? featureE;
  final String? failureReason;
  final String? modelVersion;
  final String? preprocessingVersion;
  final String? thresholdVersion;
  final DateTime createdAt;
  const WeightResult({
    required this.scanId,
    required this.eligible,
    this.valueKg,
    this.referenceLengthCm,
    this.referencePixelLength,
    this.cmPerPixel,
    this.featureRa,
    this.featureLc,
    this.featureBl,
    this.featureBw,
    this.featureE,
    this.failureReason,
    this.modelVersion,
    this.preprocessingVersion,
    this.thresholdVersion,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scan_id'] = Variable<String>(scanId);
    map['eligible'] = Variable<bool>(eligible);
    if (!nullToAbsent || valueKg != null) {
      map['value_kg'] = Variable<double>(valueKg);
    }
    if (!nullToAbsent || referenceLengthCm != null) {
      map['reference_length_cm'] = Variable<double>(referenceLengthCm);
    }
    if (!nullToAbsent || referencePixelLength != null) {
      map['reference_pixel_length'] = Variable<double>(referencePixelLength);
    }
    if (!nullToAbsent || cmPerPixel != null) {
      map['cm_per_pixel'] = Variable<double>(cmPerPixel);
    }
    if (!nullToAbsent || featureRa != null) {
      map['feature_ra'] = Variable<double>(featureRa);
    }
    if (!nullToAbsent || featureLc != null) {
      map['feature_lc'] = Variable<double>(featureLc);
    }
    if (!nullToAbsent || featureBl != null) {
      map['feature_bl'] = Variable<double>(featureBl);
    }
    if (!nullToAbsent || featureBw != null) {
      map['feature_bw'] = Variable<double>(featureBw);
    }
    if (!nullToAbsent || featureE != null) {
      map['feature_e'] = Variable<double>(featureE);
    }
    if (!nullToAbsent || failureReason != null) {
      map['failure_reason'] = Variable<String>(failureReason);
    }
    if (!nullToAbsent || modelVersion != null) {
      map['model_version'] = Variable<String>(modelVersion);
    }
    if (!nullToAbsent || preprocessingVersion != null) {
      map['preprocessing_version'] = Variable<String>(preprocessingVersion);
    }
    if (!nullToAbsent || thresholdVersion != null) {
      map['threshold_version'] = Variable<String>(thresholdVersion);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  WeightResultsCompanion toCompanion(bool nullToAbsent) {
    return WeightResultsCompanion(
      scanId: Value(scanId),
      eligible: Value(eligible),
      valueKg: valueKg == null && nullToAbsent
          ? const Value.absent()
          : Value(valueKg),
      referenceLengthCm: referenceLengthCm == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceLengthCm),
      referencePixelLength: referencePixelLength == null && nullToAbsent
          ? const Value.absent()
          : Value(referencePixelLength),
      cmPerPixel: cmPerPixel == null && nullToAbsent
          ? const Value.absent()
          : Value(cmPerPixel),
      featureRa: featureRa == null && nullToAbsent
          ? const Value.absent()
          : Value(featureRa),
      featureLc: featureLc == null && nullToAbsent
          ? const Value.absent()
          : Value(featureLc),
      featureBl: featureBl == null && nullToAbsent
          ? const Value.absent()
          : Value(featureBl),
      featureBw: featureBw == null && nullToAbsent
          ? const Value.absent()
          : Value(featureBw),
      featureE: featureE == null && nullToAbsent
          ? const Value.absent()
          : Value(featureE),
      failureReason: failureReason == null && nullToAbsent
          ? const Value.absent()
          : Value(failureReason),
      modelVersion: modelVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(modelVersion),
      preprocessingVersion: preprocessingVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(preprocessingVersion),
      thresholdVersion: thresholdVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(thresholdVersion),
      createdAt: Value(createdAt),
    );
  }

  factory WeightResult.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WeightResult(
      scanId: serializer.fromJson<String>(json['scanId']),
      eligible: serializer.fromJson<bool>(json['eligible']),
      valueKg: serializer.fromJson<double?>(json['valueKg']),
      referenceLengthCm: serializer.fromJson<double?>(
        json['referenceLengthCm'],
      ),
      referencePixelLength: serializer.fromJson<double?>(
        json['referencePixelLength'],
      ),
      cmPerPixel: serializer.fromJson<double?>(json['cmPerPixel']),
      featureRa: serializer.fromJson<double?>(json['featureRa']),
      featureLc: serializer.fromJson<double?>(json['featureLc']),
      featureBl: serializer.fromJson<double?>(json['featureBl']),
      featureBw: serializer.fromJson<double?>(json['featureBw']),
      featureE: serializer.fromJson<double?>(json['featureE']),
      failureReason: serializer.fromJson<String?>(json['failureReason']),
      modelVersion: serializer.fromJson<String?>(json['modelVersion']),
      preprocessingVersion: serializer.fromJson<String?>(
        json['preprocessingVersion'],
      ),
      thresholdVersion: serializer.fromJson<String?>(json['thresholdVersion']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scanId': serializer.toJson<String>(scanId),
      'eligible': serializer.toJson<bool>(eligible),
      'valueKg': serializer.toJson<double?>(valueKg),
      'referenceLengthCm': serializer.toJson<double?>(referenceLengthCm),
      'referencePixelLength': serializer.toJson<double?>(referencePixelLength),
      'cmPerPixel': serializer.toJson<double?>(cmPerPixel),
      'featureRa': serializer.toJson<double?>(featureRa),
      'featureLc': serializer.toJson<double?>(featureLc),
      'featureBl': serializer.toJson<double?>(featureBl),
      'featureBw': serializer.toJson<double?>(featureBw),
      'featureE': serializer.toJson<double?>(featureE),
      'failureReason': serializer.toJson<String?>(failureReason),
      'modelVersion': serializer.toJson<String?>(modelVersion),
      'preprocessingVersion': serializer.toJson<String?>(preprocessingVersion),
      'thresholdVersion': serializer.toJson<String?>(thresholdVersion),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  WeightResult copyWith({
    String? scanId,
    bool? eligible,
    Value<double?> valueKg = const Value.absent(),
    Value<double?> referenceLengthCm = const Value.absent(),
    Value<double?> referencePixelLength = const Value.absent(),
    Value<double?> cmPerPixel = const Value.absent(),
    Value<double?> featureRa = const Value.absent(),
    Value<double?> featureLc = const Value.absent(),
    Value<double?> featureBl = const Value.absent(),
    Value<double?> featureBw = const Value.absent(),
    Value<double?> featureE = const Value.absent(),
    Value<String?> failureReason = const Value.absent(),
    Value<String?> modelVersion = const Value.absent(),
    Value<String?> preprocessingVersion = const Value.absent(),
    Value<String?> thresholdVersion = const Value.absent(),
    DateTime? createdAt,
  }) => WeightResult(
    scanId: scanId ?? this.scanId,
    eligible: eligible ?? this.eligible,
    valueKg: valueKg.present ? valueKg.value : this.valueKg,
    referenceLengthCm: referenceLengthCm.present
        ? referenceLengthCm.value
        : this.referenceLengthCm,
    referencePixelLength: referencePixelLength.present
        ? referencePixelLength.value
        : this.referencePixelLength,
    cmPerPixel: cmPerPixel.present ? cmPerPixel.value : this.cmPerPixel,
    featureRa: featureRa.present ? featureRa.value : this.featureRa,
    featureLc: featureLc.present ? featureLc.value : this.featureLc,
    featureBl: featureBl.present ? featureBl.value : this.featureBl,
    featureBw: featureBw.present ? featureBw.value : this.featureBw,
    featureE: featureE.present ? featureE.value : this.featureE,
    failureReason: failureReason.present
        ? failureReason.value
        : this.failureReason,
    modelVersion: modelVersion.present ? modelVersion.value : this.modelVersion,
    preprocessingVersion: preprocessingVersion.present
        ? preprocessingVersion.value
        : this.preprocessingVersion,
    thresholdVersion: thresholdVersion.present
        ? thresholdVersion.value
        : this.thresholdVersion,
    createdAt: createdAt ?? this.createdAt,
  );
  WeightResult copyWithCompanion(WeightResultsCompanion data) {
    return WeightResult(
      scanId: data.scanId.present ? data.scanId.value : this.scanId,
      eligible: data.eligible.present ? data.eligible.value : this.eligible,
      valueKg: data.valueKg.present ? data.valueKg.value : this.valueKg,
      referenceLengthCm: data.referenceLengthCm.present
          ? data.referenceLengthCm.value
          : this.referenceLengthCm,
      referencePixelLength: data.referencePixelLength.present
          ? data.referencePixelLength.value
          : this.referencePixelLength,
      cmPerPixel: data.cmPerPixel.present
          ? data.cmPerPixel.value
          : this.cmPerPixel,
      featureRa: data.featureRa.present ? data.featureRa.value : this.featureRa,
      featureLc: data.featureLc.present ? data.featureLc.value : this.featureLc,
      featureBl: data.featureBl.present ? data.featureBl.value : this.featureBl,
      featureBw: data.featureBw.present ? data.featureBw.value : this.featureBw,
      featureE: data.featureE.present ? data.featureE.value : this.featureE,
      failureReason: data.failureReason.present
          ? data.failureReason.value
          : this.failureReason,
      modelVersion: data.modelVersion.present
          ? data.modelVersion.value
          : this.modelVersion,
      preprocessingVersion: data.preprocessingVersion.present
          ? data.preprocessingVersion.value
          : this.preprocessingVersion,
      thresholdVersion: data.thresholdVersion.present
          ? data.thresholdVersion.value
          : this.thresholdVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WeightResult(')
          ..write('scanId: $scanId, ')
          ..write('eligible: $eligible, ')
          ..write('valueKg: $valueKg, ')
          ..write('referenceLengthCm: $referenceLengthCm, ')
          ..write('referencePixelLength: $referencePixelLength, ')
          ..write('cmPerPixel: $cmPerPixel, ')
          ..write('featureRa: $featureRa, ')
          ..write('featureLc: $featureLc, ')
          ..write('featureBl: $featureBl, ')
          ..write('featureBw: $featureBw, ')
          ..write('featureE: $featureE, ')
          ..write('failureReason: $failureReason, ')
          ..write('modelVersion: $modelVersion, ')
          ..write('preprocessingVersion: $preprocessingVersion, ')
          ..write('thresholdVersion: $thresholdVersion, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    scanId,
    eligible,
    valueKg,
    referenceLengthCm,
    referencePixelLength,
    cmPerPixel,
    featureRa,
    featureLc,
    featureBl,
    featureBw,
    featureE,
    failureReason,
    modelVersion,
    preprocessingVersion,
    thresholdVersion,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WeightResult &&
          other.scanId == this.scanId &&
          other.eligible == this.eligible &&
          other.valueKg == this.valueKg &&
          other.referenceLengthCm == this.referenceLengthCm &&
          other.referencePixelLength == this.referencePixelLength &&
          other.cmPerPixel == this.cmPerPixel &&
          other.featureRa == this.featureRa &&
          other.featureLc == this.featureLc &&
          other.featureBl == this.featureBl &&
          other.featureBw == this.featureBw &&
          other.featureE == this.featureE &&
          other.failureReason == this.failureReason &&
          other.modelVersion == this.modelVersion &&
          other.preprocessingVersion == this.preprocessingVersion &&
          other.thresholdVersion == this.thresholdVersion &&
          other.createdAt == this.createdAt);
}

class WeightResultsCompanion extends UpdateCompanion<WeightResult> {
  final Value<String> scanId;
  final Value<bool> eligible;
  final Value<double?> valueKg;
  final Value<double?> referenceLengthCm;
  final Value<double?> referencePixelLength;
  final Value<double?> cmPerPixel;
  final Value<double?> featureRa;
  final Value<double?> featureLc;
  final Value<double?> featureBl;
  final Value<double?> featureBw;
  final Value<double?> featureE;
  final Value<String?> failureReason;
  final Value<String?> modelVersion;
  final Value<String?> preprocessingVersion;
  final Value<String?> thresholdVersion;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const WeightResultsCompanion({
    this.scanId = const Value.absent(),
    this.eligible = const Value.absent(),
    this.valueKg = const Value.absent(),
    this.referenceLengthCm = const Value.absent(),
    this.referencePixelLength = const Value.absent(),
    this.cmPerPixel = const Value.absent(),
    this.featureRa = const Value.absent(),
    this.featureLc = const Value.absent(),
    this.featureBl = const Value.absent(),
    this.featureBw = const Value.absent(),
    this.featureE = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.modelVersion = const Value.absent(),
    this.preprocessingVersion = const Value.absent(),
    this.thresholdVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WeightResultsCompanion.insert({
    required String scanId,
    required bool eligible,
    this.valueKg = const Value.absent(),
    this.referenceLengthCm = const Value.absent(),
    this.referencePixelLength = const Value.absent(),
    this.cmPerPixel = const Value.absent(),
    this.featureRa = const Value.absent(),
    this.featureLc = const Value.absent(),
    this.featureBl = const Value.absent(),
    this.featureBw = const Value.absent(),
    this.featureE = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.modelVersion = const Value.absent(),
    this.preprocessingVersion = const Value.absent(),
    this.thresholdVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : scanId = Value(scanId),
       eligible = Value(eligible);
  static Insertable<WeightResult> custom({
    Expression<String>? scanId,
    Expression<bool>? eligible,
    Expression<double>? valueKg,
    Expression<double>? referenceLengthCm,
    Expression<double>? referencePixelLength,
    Expression<double>? cmPerPixel,
    Expression<double>? featureRa,
    Expression<double>? featureLc,
    Expression<double>? featureBl,
    Expression<double>? featureBw,
    Expression<double>? featureE,
    Expression<String>? failureReason,
    Expression<String>? modelVersion,
    Expression<String>? preprocessingVersion,
    Expression<String>? thresholdVersion,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scanId != null) 'scan_id': scanId,
      if (eligible != null) 'eligible': eligible,
      if (valueKg != null) 'value_kg': valueKg,
      if (referenceLengthCm != null) 'reference_length_cm': referenceLengthCm,
      if (referencePixelLength != null)
        'reference_pixel_length': referencePixelLength,
      if (cmPerPixel != null) 'cm_per_pixel': cmPerPixel,
      if (featureRa != null) 'feature_ra': featureRa,
      if (featureLc != null) 'feature_lc': featureLc,
      if (featureBl != null) 'feature_bl': featureBl,
      if (featureBw != null) 'feature_bw': featureBw,
      if (featureE != null) 'feature_e': featureE,
      if (failureReason != null) 'failure_reason': failureReason,
      if (modelVersion != null) 'model_version': modelVersion,
      if (preprocessingVersion != null)
        'preprocessing_version': preprocessingVersion,
      if (thresholdVersion != null) 'threshold_version': thresholdVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WeightResultsCompanion copyWith({
    Value<String>? scanId,
    Value<bool>? eligible,
    Value<double?>? valueKg,
    Value<double?>? referenceLengthCm,
    Value<double?>? referencePixelLength,
    Value<double?>? cmPerPixel,
    Value<double?>? featureRa,
    Value<double?>? featureLc,
    Value<double?>? featureBl,
    Value<double?>? featureBw,
    Value<double?>? featureE,
    Value<String?>? failureReason,
    Value<String?>? modelVersion,
    Value<String?>? preprocessingVersion,
    Value<String?>? thresholdVersion,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return WeightResultsCompanion(
      scanId: scanId ?? this.scanId,
      eligible: eligible ?? this.eligible,
      valueKg: valueKg ?? this.valueKg,
      referenceLengthCm: referenceLengthCm ?? this.referenceLengthCm,
      referencePixelLength: referencePixelLength ?? this.referencePixelLength,
      cmPerPixel: cmPerPixel ?? this.cmPerPixel,
      featureRa: featureRa ?? this.featureRa,
      featureLc: featureLc ?? this.featureLc,
      featureBl: featureBl ?? this.featureBl,
      featureBw: featureBw ?? this.featureBw,
      featureE: featureE ?? this.featureE,
      failureReason: failureReason ?? this.failureReason,
      modelVersion: modelVersion ?? this.modelVersion,
      preprocessingVersion: preprocessingVersion ?? this.preprocessingVersion,
      thresholdVersion: thresholdVersion ?? this.thresholdVersion,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scanId.present) {
      map['scan_id'] = Variable<String>(scanId.value);
    }
    if (eligible.present) {
      map['eligible'] = Variable<bool>(eligible.value);
    }
    if (valueKg.present) {
      map['value_kg'] = Variable<double>(valueKg.value);
    }
    if (referenceLengthCm.present) {
      map['reference_length_cm'] = Variable<double>(referenceLengthCm.value);
    }
    if (referencePixelLength.present) {
      map['reference_pixel_length'] = Variable<double>(
        referencePixelLength.value,
      );
    }
    if (cmPerPixel.present) {
      map['cm_per_pixel'] = Variable<double>(cmPerPixel.value);
    }
    if (featureRa.present) {
      map['feature_ra'] = Variable<double>(featureRa.value);
    }
    if (featureLc.present) {
      map['feature_lc'] = Variable<double>(featureLc.value);
    }
    if (featureBl.present) {
      map['feature_bl'] = Variable<double>(featureBl.value);
    }
    if (featureBw.present) {
      map['feature_bw'] = Variable<double>(featureBw.value);
    }
    if (featureE.present) {
      map['feature_e'] = Variable<double>(featureE.value);
    }
    if (failureReason.present) {
      map['failure_reason'] = Variable<String>(failureReason.value);
    }
    if (modelVersion.present) {
      map['model_version'] = Variable<String>(modelVersion.value);
    }
    if (preprocessingVersion.present) {
      map['preprocessing_version'] = Variable<String>(
        preprocessingVersion.value,
      );
    }
    if (thresholdVersion.present) {
      map['threshold_version'] = Variable<String>(thresholdVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WeightResultsCompanion(')
          ..write('scanId: $scanId, ')
          ..write('eligible: $eligible, ')
          ..write('valueKg: $valueKg, ')
          ..write('referenceLengthCm: $referenceLengthCm, ')
          ..write('referencePixelLength: $referencePixelLength, ')
          ..write('cmPerPixel: $cmPerPixel, ')
          ..write('featureRa: $featureRa, ')
          ..write('featureLc: $featureLc, ')
          ..write('featureBl: $featureBl, ')
          ..write('featureBw: $featureBw, ')
          ..write('featureE: $featureE, ')
          ..write('failureReason: $failureReason, ')
          ..write('modelVersion: $modelVersion, ')
          ..write('preprocessingVersion: $preprocessingVersion, ')
          ..write('thresholdVersion: $thresholdVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HealthResultsTable extends HealthResults
    with TableInfo<$HealthResultsTable, HealthResult> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HealthResultsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scanIdMeta = const VerificationMeta('scanId');
  @override
  late final GeneratedColumn<String> scanId = GeneratedColumn<String>(
    'scan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES scan_records (id)',
    ),
  );
  static const VerificationMeta _eligibleMeta = const VerificationMeta(
    'eligible',
  );
  @override
  late final GeneratedColumn<bool> eligible = GeneratedColumn<bool>(
    'eligible',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("eligible" IN (0, 1))',
    ),
  );
  static const VerificationMeta _classNameMeta = const VerificationMeta(
    'className',
  );
  @override
  late final GeneratedColumn<String> className = GeneratedColumn<String>(
    'class_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _uncertainMeta = const VerificationMeta(
    'uncertain',
  );
  @override
  late final GeneratedColumn<bool> uncertain = GeneratedColumn<bool>(
    'uncertain',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("uncertain" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _failureReasonMeta = const VerificationMeta(
    'failureReason',
  );
  @override
  late final GeneratedColumn<String> failureReason = GeneratedColumn<String>(
    'failure_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelVersionMeta = const VerificationMeta(
    'modelVersion',
  );
  @override
  late final GeneratedColumn<String> modelVersion = GeneratedColumn<String>(
    'model_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _preprocessingVersionMeta =
      const VerificationMeta('preprocessingVersion');
  @override
  late final GeneratedColumn<String> preprocessingVersion =
      GeneratedColumn<String>(
        'preprocessing_version',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _thresholdVersionMeta = const VerificationMeta(
    'thresholdVersion',
  );
  @override
  late final GeneratedColumn<String> thresholdVersion = GeneratedColumn<String>(
    'threshold_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    scanId,
    eligible,
    className,
    confidence,
    uncertain,
    failureReason,
    modelVersion,
    preprocessingVersion,
    thresholdVersion,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'health_results';
  @override
  VerificationContext validateIntegrity(
    Insertable<HealthResult> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scan_id')) {
      context.handle(
        _scanIdMeta,
        scanId.isAcceptableOrUnknown(data['scan_id']!, _scanIdMeta),
      );
    } else if (isInserting) {
      context.missing(_scanIdMeta);
    }
    if (data.containsKey('eligible')) {
      context.handle(
        _eligibleMeta,
        eligible.isAcceptableOrUnknown(data['eligible']!, _eligibleMeta),
      );
    } else if (isInserting) {
      context.missing(_eligibleMeta);
    }
    if (data.containsKey('class_name')) {
      context.handle(
        _classNameMeta,
        className.isAcceptableOrUnknown(data['class_name']!, _classNameMeta),
      );
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    }
    if (data.containsKey('uncertain')) {
      context.handle(
        _uncertainMeta,
        uncertain.isAcceptableOrUnknown(data['uncertain']!, _uncertainMeta),
      );
    }
    if (data.containsKey('failure_reason')) {
      context.handle(
        _failureReasonMeta,
        failureReason.isAcceptableOrUnknown(
          data['failure_reason']!,
          _failureReasonMeta,
        ),
      );
    }
    if (data.containsKey('model_version')) {
      context.handle(
        _modelVersionMeta,
        modelVersion.isAcceptableOrUnknown(
          data['model_version']!,
          _modelVersionMeta,
        ),
      );
    }
    if (data.containsKey('preprocessing_version')) {
      context.handle(
        _preprocessingVersionMeta,
        preprocessingVersion.isAcceptableOrUnknown(
          data['preprocessing_version']!,
          _preprocessingVersionMeta,
        ),
      );
    }
    if (data.containsKey('threshold_version')) {
      context.handle(
        _thresholdVersionMeta,
        thresholdVersion.isAcceptableOrUnknown(
          data['threshold_version']!,
          _thresholdVersionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scanId};
  @override
  HealthResult map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HealthResult(
      scanId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scan_id'],
      )!,
      eligible: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}eligible'],
      )!,
      className: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}class_name'],
      ),
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      ),
      uncertain: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}uncertain'],
      )!,
      failureReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_reason'],
      ),
      modelVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_version'],
      ),
      preprocessingVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preprocessing_version'],
      ),
      thresholdVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}threshold_version'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $HealthResultsTable createAlias(String alias) {
    return $HealthResultsTable(attachedDatabase, alias);
  }
}

class HealthResult extends DataClass implements Insertable<HealthResult> {
  final String scanId;
  final bool eligible;
  final String? className;
  final double? confidence;
  final bool uncertain;
  final String? failureReason;
  final String? modelVersion;
  final String? preprocessingVersion;
  final String? thresholdVersion;
  final DateTime createdAt;
  const HealthResult({
    required this.scanId,
    required this.eligible,
    this.className,
    this.confidence,
    required this.uncertain,
    this.failureReason,
    this.modelVersion,
    this.preprocessingVersion,
    this.thresholdVersion,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scan_id'] = Variable<String>(scanId);
    map['eligible'] = Variable<bool>(eligible);
    if (!nullToAbsent || className != null) {
      map['class_name'] = Variable<String>(className);
    }
    if (!nullToAbsent || confidence != null) {
      map['confidence'] = Variable<double>(confidence);
    }
    map['uncertain'] = Variable<bool>(uncertain);
    if (!nullToAbsent || failureReason != null) {
      map['failure_reason'] = Variable<String>(failureReason);
    }
    if (!nullToAbsent || modelVersion != null) {
      map['model_version'] = Variable<String>(modelVersion);
    }
    if (!nullToAbsent || preprocessingVersion != null) {
      map['preprocessing_version'] = Variable<String>(preprocessingVersion);
    }
    if (!nullToAbsent || thresholdVersion != null) {
      map['threshold_version'] = Variable<String>(thresholdVersion);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  HealthResultsCompanion toCompanion(bool nullToAbsent) {
    return HealthResultsCompanion(
      scanId: Value(scanId),
      eligible: Value(eligible),
      className: className == null && nullToAbsent
          ? const Value.absent()
          : Value(className),
      confidence: confidence == null && nullToAbsent
          ? const Value.absent()
          : Value(confidence),
      uncertain: Value(uncertain),
      failureReason: failureReason == null && nullToAbsent
          ? const Value.absent()
          : Value(failureReason),
      modelVersion: modelVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(modelVersion),
      preprocessingVersion: preprocessingVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(preprocessingVersion),
      thresholdVersion: thresholdVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(thresholdVersion),
      createdAt: Value(createdAt),
    );
  }

  factory HealthResult.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HealthResult(
      scanId: serializer.fromJson<String>(json['scanId']),
      eligible: serializer.fromJson<bool>(json['eligible']),
      className: serializer.fromJson<String?>(json['className']),
      confidence: serializer.fromJson<double?>(json['confidence']),
      uncertain: serializer.fromJson<bool>(json['uncertain']),
      failureReason: serializer.fromJson<String?>(json['failureReason']),
      modelVersion: serializer.fromJson<String?>(json['modelVersion']),
      preprocessingVersion: serializer.fromJson<String?>(
        json['preprocessingVersion'],
      ),
      thresholdVersion: serializer.fromJson<String?>(json['thresholdVersion']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scanId': serializer.toJson<String>(scanId),
      'eligible': serializer.toJson<bool>(eligible),
      'className': serializer.toJson<String?>(className),
      'confidence': serializer.toJson<double?>(confidence),
      'uncertain': serializer.toJson<bool>(uncertain),
      'failureReason': serializer.toJson<String?>(failureReason),
      'modelVersion': serializer.toJson<String?>(modelVersion),
      'preprocessingVersion': serializer.toJson<String?>(preprocessingVersion),
      'thresholdVersion': serializer.toJson<String?>(thresholdVersion),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  HealthResult copyWith({
    String? scanId,
    bool? eligible,
    Value<String?> className = const Value.absent(),
    Value<double?> confidence = const Value.absent(),
    bool? uncertain,
    Value<String?> failureReason = const Value.absent(),
    Value<String?> modelVersion = const Value.absent(),
    Value<String?> preprocessingVersion = const Value.absent(),
    Value<String?> thresholdVersion = const Value.absent(),
    DateTime? createdAt,
  }) => HealthResult(
    scanId: scanId ?? this.scanId,
    eligible: eligible ?? this.eligible,
    className: className.present ? className.value : this.className,
    confidence: confidence.present ? confidence.value : this.confidence,
    uncertain: uncertain ?? this.uncertain,
    failureReason: failureReason.present
        ? failureReason.value
        : this.failureReason,
    modelVersion: modelVersion.present ? modelVersion.value : this.modelVersion,
    preprocessingVersion: preprocessingVersion.present
        ? preprocessingVersion.value
        : this.preprocessingVersion,
    thresholdVersion: thresholdVersion.present
        ? thresholdVersion.value
        : this.thresholdVersion,
    createdAt: createdAt ?? this.createdAt,
  );
  HealthResult copyWithCompanion(HealthResultsCompanion data) {
    return HealthResult(
      scanId: data.scanId.present ? data.scanId.value : this.scanId,
      eligible: data.eligible.present ? data.eligible.value : this.eligible,
      className: data.className.present ? data.className.value : this.className,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      uncertain: data.uncertain.present ? data.uncertain.value : this.uncertain,
      failureReason: data.failureReason.present
          ? data.failureReason.value
          : this.failureReason,
      modelVersion: data.modelVersion.present
          ? data.modelVersion.value
          : this.modelVersion,
      preprocessingVersion: data.preprocessingVersion.present
          ? data.preprocessingVersion.value
          : this.preprocessingVersion,
      thresholdVersion: data.thresholdVersion.present
          ? data.thresholdVersion.value
          : this.thresholdVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HealthResult(')
          ..write('scanId: $scanId, ')
          ..write('eligible: $eligible, ')
          ..write('className: $className, ')
          ..write('confidence: $confidence, ')
          ..write('uncertain: $uncertain, ')
          ..write('failureReason: $failureReason, ')
          ..write('modelVersion: $modelVersion, ')
          ..write('preprocessingVersion: $preprocessingVersion, ')
          ..write('thresholdVersion: $thresholdVersion, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    scanId,
    eligible,
    className,
    confidence,
    uncertain,
    failureReason,
    modelVersion,
    preprocessingVersion,
    thresholdVersion,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HealthResult &&
          other.scanId == this.scanId &&
          other.eligible == this.eligible &&
          other.className == this.className &&
          other.confidence == this.confidence &&
          other.uncertain == this.uncertain &&
          other.failureReason == this.failureReason &&
          other.modelVersion == this.modelVersion &&
          other.preprocessingVersion == this.preprocessingVersion &&
          other.thresholdVersion == this.thresholdVersion &&
          other.createdAt == this.createdAt);
}

class HealthResultsCompanion extends UpdateCompanion<HealthResult> {
  final Value<String> scanId;
  final Value<bool> eligible;
  final Value<String?> className;
  final Value<double?> confidence;
  final Value<bool> uncertain;
  final Value<String?> failureReason;
  final Value<String?> modelVersion;
  final Value<String?> preprocessingVersion;
  final Value<String?> thresholdVersion;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const HealthResultsCompanion({
    this.scanId = const Value.absent(),
    this.eligible = const Value.absent(),
    this.className = const Value.absent(),
    this.confidence = const Value.absent(),
    this.uncertain = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.modelVersion = const Value.absent(),
    this.preprocessingVersion = const Value.absent(),
    this.thresholdVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HealthResultsCompanion.insert({
    required String scanId,
    required bool eligible,
    this.className = const Value.absent(),
    this.confidence = const Value.absent(),
    this.uncertain = const Value.absent(),
    this.failureReason = const Value.absent(),
    this.modelVersion = const Value.absent(),
    this.preprocessingVersion = const Value.absent(),
    this.thresholdVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : scanId = Value(scanId),
       eligible = Value(eligible);
  static Insertable<HealthResult> custom({
    Expression<String>? scanId,
    Expression<bool>? eligible,
    Expression<String>? className,
    Expression<double>? confidence,
    Expression<bool>? uncertain,
    Expression<String>? failureReason,
    Expression<String>? modelVersion,
    Expression<String>? preprocessingVersion,
    Expression<String>? thresholdVersion,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scanId != null) 'scan_id': scanId,
      if (eligible != null) 'eligible': eligible,
      if (className != null) 'class_name': className,
      if (confidence != null) 'confidence': confidence,
      if (uncertain != null) 'uncertain': uncertain,
      if (failureReason != null) 'failure_reason': failureReason,
      if (modelVersion != null) 'model_version': modelVersion,
      if (preprocessingVersion != null)
        'preprocessing_version': preprocessingVersion,
      if (thresholdVersion != null) 'threshold_version': thresholdVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HealthResultsCompanion copyWith({
    Value<String>? scanId,
    Value<bool>? eligible,
    Value<String?>? className,
    Value<double?>? confidence,
    Value<bool>? uncertain,
    Value<String?>? failureReason,
    Value<String?>? modelVersion,
    Value<String?>? preprocessingVersion,
    Value<String?>? thresholdVersion,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return HealthResultsCompanion(
      scanId: scanId ?? this.scanId,
      eligible: eligible ?? this.eligible,
      className: className ?? this.className,
      confidence: confidence ?? this.confidence,
      uncertain: uncertain ?? this.uncertain,
      failureReason: failureReason ?? this.failureReason,
      modelVersion: modelVersion ?? this.modelVersion,
      preprocessingVersion: preprocessingVersion ?? this.preprocessingVersion,
      thresholdVersion: thresholdVersion ?? this.thresholdVersion,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scanId.present) {
      map['scan_id'] = Variable<String>(scanId.value);
    }
    if (eligible.present) {
      map['eligible'] = Variable<bool>(eligible.value);
    }
    if (className.present) {
      map['class_name'] = Variable<String>(className.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (uncertain.present) {
      map['uncertain'] = Variable<bool>(uncertain.value);
    }
    if (failureReason.present) {
      map['failure_reason'] = Variable<String>(failureReason.value);
    }
    if (modelVersion.present) {
      map['model_version'] = Variable<String>(modelVersion.value);
    }
    if (preprocessingVersion.present) {
      map['preprocessing_version'] = Variable<String>(
        preprocessingVersion.value,
      );
    }
    if (thresholdVersion.present) {
      map['threshold_version'] = Variable<String>(thresholdVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HealthResultsCompanion(')
          ..write('scanId: $scanId, ')
          ..write('eligible: $eligible, ')
          ..write('className: $className, ')
          ..write('confidence: $confidence, ')
          ..write('uncertain: $uncertain, ')
          ..write('failureReason: $failureReason, ')
          ..write('modelVersion: $modelVersion, ')
          ..write('preprocessingVersion: $preprocessingVersion, ')
          ..write('thresholdVersion: $thresholdVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PipelineEventsTable extends PipelineEvents
    with TableInfo<$PipelineEventsTable, PipelineEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PipelineEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _scanIdMeta = const VerificationMeta('scanId');
  @override
  late final GeneratedColumn<String> scanId = GeneratedColumn<String>(
    'scan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES scan_records (id)',
    ),
  );
  static const VerificationMeta _stageMeta = const VerificationMeta('stage');
  @override
  late final GeneratedColumn<String> stage = GeneratedColumn<String>(
    'stage',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    scanId,
    stage,
    status,
    message,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pipeline_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<PipelineEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('scan_id')) {
      context.handle(
        _scanIdMeta,
        scanId.isAcceptableOrUnknown(data['scan_id']!, _scanIdMeta),
      );
    } else if (isInserting) {
      context.missing(_scanIdMeta);
    }
    if (data.containsKey('stage')) {
      context.handle(
        _stageMeta,
        stage.isAcceptableOrUnknown(data['stage']!, _stageMeta),
      );
    } else if (isInserting) {
      context.missing(_stageMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PipelineEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PipelineEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      scanId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scan_id'],
      )!,
      stage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stage'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PipelineEventsTable createAlias(String alias) {
    return $PipelineEventsTable(attachedDatabase, alias);
  }
}

class PipelineEvent extends DataClass implements Insertable<PipelineEvent> {
  final int id;
  final String scanId;
  final String stage;
  final String status;
  final String? message;
  final DateTime createdAt;
  const PipelineEvent({
    required this.id,
    required this.scanId,
    required this.stage,
    required this.status,
    this.message,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['scan_id'] = Variable<String>(scanId);
    map['stage'] = Variable<String>(stage);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || message != null) {
      map['message'] = Variable<String>(message);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PipelineEventsCompanion toCompanion(bool nullToAbsent) {
    return PipelineEventsCompanion(
      id: Value(id),
      scanId: Value(scanId),
      stage: Value(stage),
      status: Value(status),
      message: message == null && nullToAbsent
          ? const Value.absent()
          : Value(message),
      createdAt: Value(createdAt),
    );
  }

  factory PipelineEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PipelineEvent(
      id: serializer.fromJson<int>(json['id']),
      scanId: serializer.fromJson<String>(json['scanId']),
      stage: serializer.fromJson<String>(json['stage']),
      status: serializer.fromJson<String>(json['status']),
      message: serializer.fromJson<String?>(json['message']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'scanId': serializer.toJson<String>(scanId),
      'stage': serializer.toJson<String>(stage),
      'status': serializer.toJson<String>(status),
      'message': serializer.toJson<String?>(message),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PipelineEvent copyWith({
    int? id,
    String? scanId,
    String? stage,
    String? status,
    Value<String?> message = const Value.absent(),
    DateTime? createdAt,
  }) => PipelineEvent(
    id: id ?? this.id,
    scanId: scanId ?? this.scanId,
    stage: stage ?? this.stage,
    status: status ?? this.status,
    message: message.present ? message.value : this.message,
    createdAt: createdAt ?? this.createdAt,
  );
  PipelineEvent copyWithCompanion(PipelineEventsCompanion data) {
    return PipelineEvent(
      id: data.id.present ? data.id.value : this.id,
      scanId: data.scanId.present ? data.scanId.value : this.scanId,
      stage: data.stage.present ? data.stage.value : this.stage,
      status: data.status.present ? data.status.value : this.status,
      message: data.message.present ? data.message.value : this.message,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PipelineEvent(')
          ..write('id: $id, ')
          ..write('scanId: $scanId, ')
          ..write('stage: $stage, ')
          ..write('status: $status, ')
          ..write('message: $message, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, scanId, stage, status, message, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PipelineEvent &&
          other.id == this.id &&
          other.scanId == this.scanId &&
          other.stage == this.stage &&
          other.status == this.status &&
          other.message == this.message &&
          other.createdAt == this.createdAt);
}

class PipelineEventsCompanion extends UpdateCompanion<PipelineEvent> {
  final Value<int> id;
  final Value<String> scanId;
  final Value<String> stage;
  final Value<String> status;
  final Value<String?> message;
  final Value<DateTime> createdAt;
  const PipelineEventsCompanion({
    this.id = const Value.absent(),
    this.scanId = const Value.absent(),
    this.stage = const Value.absent(),
    this.status = const Value.absent(),
    this.message = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  PipelineEventsCompanion.insert({
    this.id = const Value.absent(),
    required String scanId,
    required String stage,
    required String status,
    this.message = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : scanId = Value(scanId),
       stage = Value(stage),
       status = Value(status);
  static Insertable<PipelineEvent> custom({
    Expression<int>? id,
    Expression<String>? scanId,
    Expression<String>? stage,
    Expression<String>? status,
    Expression<String>? message,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (scanId != null) 'scan_id': scanId,
      if (stage != null) 'stage': stage,
      if (status != null) 'status': status,
      if (message != null) 'message': message,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  PipelineEventsCompanion copyWith({
    Value<int>? id,
    Value<String>? scanId,
    Value<String>? stage,
    Value<String>? status,
    Value<String?>? message,
    Value<DateTime>? createdAt,
  }) {
    return PipelineEventsCompanion(
      id: id ?? this.id,
      scanId: scanId ?? this.scanId,
      stage: stage ?? this.stage,
      status: status ?? this.status,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (scanId.present) {
      map['scan_id'] = Variable<String>(scanId.value);
    }
    if (stage.present) {
      map['stage'] = Variable<String>(stage.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PipelineEventsCompanion(')
          ..write('id: $id, ')
          ..write('scanId: $scanId, ')
          ..write('stage: $stage, ')
          ..write('status: $status, ')
          ..write('message: $message, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $PrivacyPreferencesTable extends PrivacyPreferences
    with TableInfo<$PrivacyPreferencesTable, PrivacyPreference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PrivacyPreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _researchImageSharingMeta =
      const VerificationMeta('researchImageSharing');
  @override
  late final GeneratedColumn<bool> researchImageSharing = GeneratedColumn<bool>(
    'research_image_sharing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("research_image_sharing" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _usageAnalyticsMeta = const VerificationMeta(
    'usageAnalytics',
  );
  @override
  late final GeneratedColumn<bool> usageAnalytics = GeneratedColumn<bool>(
    'usage_analytics',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("usage_analytics" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _inferenceModeMeta = const VerificationMeta(
    'inferenceMode',
  );
  @override
  late final GeneratedColumn<String> inferenceMode = GeneratedColumn<String>(
    'inference_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('undecided'),
  );
  static const VerificationMeta _retentionDaysMeta = const VerificationMeta(
    'retentionDays',
  );
  @override
  late final GeneratedColumn<int> retentionDays = GeneratedColumn<int>(
    'retention_days',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    researchImageSharing,
    usageAnalytics,
    inferenceMode,
    retentionDays,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'privacy_preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<PrivacyPreference> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('research_image_sharing')) {
      context.handle(
        _researchImageSharingMeta,
        researchImageSharing.isAcceptableOrUnknown(
          data['research_image_sharing']!,
          _researchImageSharingMeta,
        ),
      );
    }
    if (data.containsKey('usage_analytics')) {
      context.handle(
        _usageAnalyticsMeta,
        usageAnalytics.isAcceptableOrUnknown(
          data['usage_analytics']!,
          _usageAnalyticsMeta,
        ),
      );
    }
    if (data.containsKey('inference_mode')) {
      context.handle(
        _inferenceModeMeta,
        inferenceMode.isAcceptableOrUnknown(
          data['inference_mode']!,
          _inferenceModeMeta,
        ),
      );
    }
    if (data.containsKey('retention_days')) {
      context.handle(
        _retentionDaysMeta,
        retentionDays.isAcceptableOrUnknown(
          data['retention_days']!,
          _retentionDaysMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PrivacyPreference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PrivacyPreference(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      researchImageSharing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}research_image_sharing'],
      )!,
      usageAnalytics: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}usage_analytics'],
      )!,
      inferenceMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}inference_mode'],
      )!,
      retentionDays: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retention_days'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PrivacyPreferencesTable createAlias(String alias) {
    return $PrivacyPreferencesTable(attachedDatabase, alias);
  }
}

class PrivacyPreference extends DataClass
    implements Insertable<PrivacyPreference> {
  final int id;
  final bool researchImageSharing;
  final bool usageAnalytics;
  final String inferenceMode;
  final int? retentionDays;
  final DateTime updatedAt;
  const PrivacyPreference({
    required this.id,
    required this.researchImageSharing,
    required this.usageAnalytics,
    required this.inferenceMode,
    this.retentionDays,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['research_image_sharing'] = Variable<bool>(researchImageSharing);
    map['usage_analytics'] = Variable<bool>(usageAnalytics);
    map['inference_mode'] = Variable<String>(inferenceMode);
    if (!nullToAbsent || retentionDays != null) {
      map['retention_days'] = Variable<int>(retentionDays);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PrivacyPreferencesCompanion toCompanion(bool nullToAbsent) {
    return PrivacyPreferencesCompanion(
      id: Value(id),
      researchImageSharing: Value(researchImageSharing),
      usageAnalytics: Value(usageAnalytics),
      inferenceMode: Value(inferenceMode),
      retentionDays: retentionDays == null && nullToAbsent
          ? const Value.absent()
          : Value(retentionDays),
      updatedAt: Value(updatedAt),
    );
  }

  factory PrivacyPreference.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PrivacyPreference(
      id: serializer.fromJson<int>(json['id']),
      researchImageSharing: serializer.fromJson<bool>(
        json['researchImageSharing'],
      ),
      usageAnalytics: serializer.fromJson<bool>(json['usageAnalytics']),
      inferenceMode: serializer.fromJson<String>(json['inferenceMode']),
      retentionDays: serializer.fromJson<int?>(json['retentionDays']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'researchImageSharing': serializer.toJson<bool>(researchImageSharing),
      'usageAnalytics': serializer.toJson<bool>(usageAnalytics),
      'inferenceMode': serializer.toJson<String>(inferenceMode),
      'retentionDays': serializer.toJson<int?>(retentionDays),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PrivacyPreference copyWith({
    int? id,
    bool? researchImageSharing,
    bool? usageAnalytics,
    String? inferenceMode,
    Value<int?> retentionDays = const Value.absent(),
    DateTime? updatedAt,
  }) => PrivacyPreference(
    id: id ?? this.id,
    researchImageSharing: researchImageSharing ?? this.researchImageSharing,
    usageAnalytics: usageAnalytics ?? this.usageAnalytics,
    inferenceMode: inferenceMode ?? this.inferenceMode,
    retentionDays: retentionDays.present
        ? retentionDays.value
        : this.retentionDays,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PrivacyPreference copyWithCompanion(PrivacyPreferencesCompanion data) {
    return PrivacyPreference(
      id: data.id.present ? data.id.value : this.id,
      researchImageSharing: data.researchImageSharing.present
          ? data.researchImageSharing.value
          : this.researchImageSharing,
      usageAnalytics: data.usageAnalytics.present
          ? data.usageAnalytics.value
          : this.usageAnalytics,
      inferenceMode: data.inferenceMode.present
          ? data.inferenceMode.value
          : this.inferenceMode,
      retentionDays: data.retentionDays.present
          ? data.retentionDays.value
          : this.retentionDays,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PrivacyPreference(')
          ..write('id: $id, ')
          ..write('researchImageSharing: $researchImageSharing, ')
          ..write('usageAnalytics: $usageAnalytics, ')
          ..write('inferenceMode: $inferenceMode, ')
          ..write('retentionDays: $retentionDays, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    researchImageSharing,
    usageAnalytics,
    inferenceMode,
    retentionDays,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PrivacyPreference &&
          other.id == this.id &&
          other.researchImageSharing == this.researchImageSharing &&
          other.usageAnalytics == this.usageAnalytics &&
          other.inferenceMode == this.inferenceMode &&
          other.retentionDays == this.retentionDays &&
          other.updatedAt == this.updatedAt);
}

class PrivacyPreferencesCompanion extends UpdateCompanion<PrivacyPreference> {
  final Value<int> id;
  final Value<bool> researchImageSharing;
  final Value<bool> usageAnalytics;
  final Value<String> inferenceMode;
  final Value<int?> retentionDays;
  final Value<DateTime> updatedAt;
  const PrivacyPreferencesCompanion({
    this.id = const Value.absent(),
    this.researchImageSharing = const Value.absent(),
    this.usageAnalytics = const Value.absent(),
    this.inferenceMode = const Value.absent(),
    this.retentionDays = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  PrivacyPreferencesCompanion.insert({
    this.id = const Value.absent(),
    this.researchImageSharing = const Value.absent(),
    this.usageAnalytics = const Value.absent(),
    this.inferenceMode = const Value.absent(),
    this.retentionDays = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  static Insertable<PrivacyPreference> custom({
    Expression<int>? id,
    Expression<bool>? researchImageSharing,
    Expression<bool>? usageAnalytics,
    Expression<String>? inferenceMode,
    Expression<int>? retentionDays,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (researchImageSharing != null)
        'research_image_sharing': researchImageSharing,
      if (usageAnalytics != null) 'usage_analytics': usageAnalytics,
      if (inferenceMode != null) 'inference_mode': inferenceMode,
      if (retentionDays != null) 'retention_days': retentionDays,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  PrivacyPreferencesCompanion copyWith({
    Value<int>? id,
    Value<bool>? researchImageSharing,
    Value<bool>? usageAnalytics,
    Value<String>? inferenceMode,
    Value<int?>? retentionDays,
    Value<DateTime>? updatedAt,
  }) {
    return PrivacyPreferencesCompanion(
      id: id ?? this.id,
      researchImageSharing: researchImageSharing ?? this.researchImageSharing,
      usageAnalytics: usageAnalytics ?? this.usageAnalytics,
      inferenceMode: inferenceMode ?? this.inferenceMode,
      retentionDays: retentionDays ?? this.retentionDays,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (researchImageSharing.present) {
      map['research_image_sharing'] = Variable<bool>(
        researchImageSharing.value,
      );
    }
    if (usageAnalytics.present) {
      map['usage_analytics'] = Variable<bool>(usageAnalytics.value);
    }
    if (inferenceMode.present) {
      map['inference_mode'] = Variable<String>(inferenceMode.value);
    }
    if (retentionDays.present) {
      map['retention_days'] = Variable<int>(retentionDays.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PrivacyPreferencesCompanion(')
          ..write('id: $id, ')
          ..write('researchImageSharing: $researchImageSharing, ')
          ..write('usageAnalytics: $usageAnalytics, ')
          ..write('inferenceMode: $inferenceMode, ')
          ..write('retentionDays: $retentionDays, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $SyncOutboxEntriesTable extends SyncOutboxEntries
    with TableInfo<$SyncOutboxEntriesTable, SyncOutboxEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOutboxEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entityType,
    entityId,
    operation,
    payloadJson,
    state,
    attempts,
    lastError,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_outbox_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOutboxEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncOutboxEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOutboxEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SyncOutboxEntriesTable createAlias(String alias) {
    return $SyncOutboxEntriesTable(attachedDatabase, alias);
  }
}

class SyncOutboxEntry extends DataClass implements Insertable<SyncOutboxEntry> {
  final int id;
  final String entityType;
  final String entityId;
  final String operation;
  final String payloadJson;
  final String state;
  final int attempts;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SyncOutboxEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payloadJson,
    required this.state,
    required this.attempts,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<String>(entityId);
    map['operation'] = Variable<String>(operation);
    map['payload_json'] = Variable<String>(payloadJson);
    map['state'] = Variable<String>(state);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SyncOutboxEntriesCompanion toCompanion(bool nullToAbsent) {
    return SyncOutboxEntriesCompanion(
      id: Value(id),
      entityType: Value(entityType),
      entityId: Value(entityId),
      operation: Value(operation),
      payloadJson: Value(payloadJson),
      state: Value(state),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncOutboxEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOutboxEntry(
      id: serializer.fromJson<int>(json['id']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<String>(json['entityId']),
      operation: serializer.fromJson<String>(json['operation']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      state: serializer.fromJson<String>(json['state']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<String>(entityId),
      'operation': serializer.toJson<String>(operation),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'state': serializer.toJson<String>(state),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SyncOutboxEntry copyWith({
    int? id,
    String? entityType,
    String? entityId,
    String? operation,
    String? payloadJson,
    String? state,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SyncOutboxEntry(
    id: id ?? this.id,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    operation: operation ?? this.operation,
    payloadJson: payloadJson ?? this.payloadJson,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncOutboxEntry copyWithCompanion(SyncOutboxEntriesCompanion data) {
    return SyncOutboxEntry(
      id: data.id.present ? data.id.value : this.id,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      operation: data.operation.present ? data.operation.value : this.operation,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      state: data.state.present ? data.state.value : this.state,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxEntry(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entityType,
    entityId,
    operation,
    payloadJson,
    state,
    attempts,
    lastError,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOutboxEntry &&
          other.id == this.id &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.operation == this.operation &&
          other.payloadJson == this.payloadJson &&
          other.state == this.state &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SyncOutboxEntriesCompanion extends UpdateCompanion<SyncOutboxEntry> {
  final Value<int> id;
  final Value<String> entityType;
  final Value<String> entityId;
  final Value<String> operation;
  final Value<String> payloadJson;
  final Value<String> state;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const SyncOutboxEntriesCompanion({
    this.id = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.operation = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  SyncOutboxEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String entityType,
    required String entityId,
    required String operation,
    required String payloadJson,
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : entityType = Value(entityType),
       entityId = Value(entityId),
       operation = Value(operation),
       payloadJson = Value(payloadJson);
  static Insertable<SyncOutboxEntry> custom({
    Expression<int>? id,
    Expression<String>? entityType,
    Expression<String>? entityId,
    Expression<String>? operation,
    Expression<String>? payloadJson,
    Expression<String>? state,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (operation != null) 'operation': operation,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (state != null) 'state': state,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  SyncOutboxEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? entityType,
    Value<String>? entityId,
    Value<String>? operation,
    Value<String>? payloadJson,
    Value<String>? state,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return SyncOutboxEntriesCompanion(
      id: id ?? this.id,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      operation: operation ?? this.operation,
      payloadJson: payloadJson ?? this.payloadJson,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxEntriesCompanion(')
          ..write('id: $id, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('operation: $operation, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PigsTable pigs = $PigsTable(this);
  late final $ScanRecordsTable scanRecords = $ScanRecordsTable(this);
  late final $ReferenceAnnotationsTable referenceAnnotations =
      $ReferenceAnnotationsTable(this);
  late final $WeightResultsTable weightResults = $WeightResultsTable(this);
  late final $HealthResultsTable healthResults = $HealthResultsTable(this);
  late final $PipelineEventsTable pipelineEvents = $PipelineEventsTable(this);
  late final $PrivacyPreferencesTable privacyPreferences =
      $PrivacyPreferencesTable(this);
  late final $SyncOutboxEntriesTable syncOutboxEntries =
      $SyncOutboxEntriesTable(this);
  late final AnalyticsDao analyticsDao = AnalyticsDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    pigs,
    scanRecords,
    referenceAnnotations,
    weightResults,
    healthResults,
    pipelineEvents,
    privacyPreferences,
    syncOutboxEntries,
  ];
}

typedef $$PigsTableCreateCompanionBuilder =
    PigsCompanion Function({
      required String id,
      Value<String?> tag,
      Value<String?> displayName,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });
typedef $$PigsTableUpdateCompanionBuilder =
    PigsCompanion Function({
      Value<String> id,
      Value<String?> tag,
      Value<String?> displayName,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<int> rowid,
    });

final class $$PigsTableReferences
    extends BaseReferences<_$AppDatabase, $PigsTable, Pig> {
  $$PigsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ScanRecordsTable, List<ScanRecord>>
  _scanRecordsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.scanRecords,
    aliasName: $_aliasNameGenerator(db.pigs.id, db.scanRecords.pigId),
  );

  $$ScanRecordsTableProcessedTableManager get scanRecordsRefs {
    final manager = $$ScanRecordsTableTableManager(
      $_db,
      $_db.scanRecords,
    ).filter((f) => f.pigId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_scanRecordsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PigsTableFilterComposer extends Composer<_$AppDatabase, $PigsTable> {
  $$PigsTableFilterComposer({
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

  ColumnFilters<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> scanRecordsRefs(
    Expression<bool> Function($$ScanRecordsTableFilterComposer f) f,
  ) {
    final $$ScanRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scanRecords,
      getReferencedColumn: (t) => t.pigId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanRecordsTableFilterComposer(
            $db: $db,
            $table: $db.scanRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PigsTableOrderingComposer extends Composer<_$AppDatabase, $PigsTable> {
  $$PigsTableOrderingComposer({
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

  ColumnOrderings<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PigsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PigsTable> {
  $$PigsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get tag =>
      $composableBuilder(column: $table.tag, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> scanRecordsRefs<T extends Object>(
    Expression<T> Function($$ScanRecordsTableAnnotationComposer a) f,
  ) {
    final $$ScanRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.scanRecords,
      getReferencedColumn: (t) => t.pigId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.scanRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PigsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PigsTable,
          Pig,
          $$PigsTableFilterComposer,
          $$PigsTableOrderingComposer,
          $$PigsTableAnnotationComposer,
          $$PigsTableCreateCompanionBuilder,
          $$PigsTableUpdateCompanionBuilder,
          (Pig, $$PigsTableReferences),
          Pig,
          PrefetchHooks Function({bool scanRecordsRefs})
        > {
  $$PigsTableTableManager(_$AppDatabase db, $PigsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PigsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PigsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PigsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> tag = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PigsCompanion(
                id: id,
                tag: tag,
                displayName: displayName,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> tag = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PigsCompanion.insert(
                id: id,
                tag: tag,
                displayName: displayName,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$PigsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({scanRecordsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (scanRecordsRefs) db.scanRecords],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (scanRecordsRefs)
                    await $_getPrefetchedData<Pig, $PigsTable, ScanRecord>(
                      currentTable: table,
                      referencedTable: $$PigsTableReferences
                          ._scanRecordsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$PigsTableReferences(db, table, p0).scanRecordsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.pigId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$PigsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PigsTable,
      Pig,
      $$PigsTableFilterComposer,
      $$PigsTableOrderingComposer,
      $$PigsTableAnnotationComposer,
      $$PigsTableCreateCompanionBuilder,
      $$PigsTableUpdateCompanionBuilder,
      (Pig, $$PigsTableReferences),
      Pig,
      PrefetchHooks Function({bool scanRecordsRefs})
    >;
typedef $$ScanRecordsTableCreateCompanionBuilder =
    ScanRecordsCompanion Function({
      required String id,
      Value<String?> pigId,
      required String goal,
      Value<String> status,
      Value<String?> imagePath,
      Value<String?> failureCode,
      Value<String?> failureMessage,
      Value<String?> notes,
      Value<DateTime?> capturedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String> syncState,
      Value<String?> remoteId,
      Value<int> rowid,
    });
typedef $$ScanRecordsTableUpdateCompanionBuilder =
    ScanRecordsCompanion Function({
      Value<String> id,
      Value<String?> pigId,
      Value<String> goal,
      Value<String> status,
      Value<String?> imagePath,
      Value<String?> failureCode,
      Value<String?> failureMessage,
      Value<String?> notes,
      Value<DateTime?> capturedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String> syncState,
      Value<String?> remoteId,
      Value<int> rowid,
    });

final class $$ScanRecordsTableReferences
    extends BaseReferences<_$AppDatabase, $ScanRecordsTable, ScanRecord> {
  $$ScanRecordsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PigsTable _pigIdTable(_$AppDatabase db) => db.pigs.createAlias(
    $_aliasNameGenerator(db.scanRecords.pigId, db.pigs.id),
  );

  $$PigsTableProcessedTableManager? get pigId {
    final $_column = $_itemColumn<String>('pig_id');
    if ($_column == null) return null;
    final manager = $$PigsTableTableManager(
      $_db,
      $_db.pigs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_pigIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $ReferenceAnnotationsTable,
    List<ReferenceAnnotation>
  >
  _referenceAnnotationsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.referenceAnnotations,
        aliasName: $_aliasNameGenerator(
          db.scanRecords.id,
          db.referenceAnnotations.scanId,
        ),
      );

  $$ReferenceAnnotationsTableProcessedTableManager
  get referenceAnnotationsRefs {
    final manager = $$ReferenceAnnotationsTableTableManager(
      $_db,
      $_db.referenceAnnotations,
    ).filter((f) => f.scanId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _referenceAnnotationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$WeightResultsTable, List<WeightResult>>
  _weightResultsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.weightResults,
    aliasName: $_aliasNameGenerator(db.scanRecords.id, db.weightResults.scanId),
  );

  $$WeightResultsTableProcessedTableManager get weightResultsRefs {
    final manager = $$WeightResultsTableTableManager(
      $_db,
      $_db.weightResults,
    ).filter((f) => f.scanId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_weightResultsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$HealthResultsTable, List<HealthResult>>
  _healthResultsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.healthResults,
    aliasName: $_aliasNameGenerator(db.scanRecords.id, db.healthResults.scanId),
  );

  $$HealthResultsTableProcessedTableManager get healthResultsRefs {
    final manager = $$HealthResultsTableTableManager(
      $_db,
      $_db.healthResults,
    ).filter((f) => f.scanId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_healthResultsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PipelineEventsTable, List<PipelineEvent>>
  _pipelineEventsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.pipelineEvents,
    aliasName: $_aliasNameGenerator(
      db.scanRecords.id,
      db.pipelineEvents.scanId,
    ),
  );

  $$PipelineEventsTableProcessedTableManager get pipelineEventsRefs {
    final manager = $$PipelineEventsTableTableManager(
      $_db,
      $_db.pipelineEvents,
    ).filter((f) => f.scanId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_pipelineEventsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ScanRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $ScanRecordsTable> {
  $$ScanRecordsTableFilterComposer({
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

  ColumnFilters<String> get goal => $composableBuilder(
    column: $table.goal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureMessage => $composableBuilder(
    column: $table.failureMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  $$PigsTableFilterComposer get pigId {
    final $$PigsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.pigId,
      referencedTable: $db.pigs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PigsTableFilterComposer(
            $db: $db,
            $table: $db.pigs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> referenceAnnotationsRefs(
    Expression<bool> Function($$ReferenceAnnotationsTableFilterComposer f) f,
  ) {
    final $$ReferenceAnnotationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.referenceAnnotations,
      getReferencedColumn: (t) => t.scanId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReferenceAnnotationsTableFilterComposer(
            $db: $db,
            $table: $db.referenceAnnotations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> weightResultsRefs(
    Expression<bool> Function($$WeightResultsTableFilterComposer f) f,
  ) {
    final $$WeightResultsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.weightResults,
      getReferencedColumn: (t) => t.scanId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WeightResultsTableFilterComposer(
            $db: $db,
            $table: $db.weightResults,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> healthResultsRefs(
    Expression<bool> Function($$HealthResultsTableFilterComposer f) f,
  ) {
    final $$HealthResultsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.healthResults,
      getReferencedColumn: (t) => t.scanId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HealthResultsTableFilterComposer(
            $db: $db,
            $table: $db.healthResults,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> pipelineEventsRefs(
    Expression<bool> Function($$PipelineEventsTableFilterComposer f) f,
  ) {
    final $$PipelineEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.pipelineEvents,
      getReferencedColumn: (t) => t.scanId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PipelineEventsTableFilterComposer(
            $db: $db,
            $table: $db.pipelineEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ScanRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $ScanRecordsTable> {
  $$ScanRecordsTableOrderingComposer({
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

  ColumnOrderings<String> get goal => $composableBuilder(
    column: $table.goal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imagePath => $composableBuilder(
    column: $table.imagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureMessage => $composableBuilder(
    column: $table.failureMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );

  $$PigsTableOrderingComposer get pigId {
    final $$PigsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.pigId,
      referencedTable: $db.pigs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PigsTableOrderingComposer(
            $db: $db,
            $table: $db.pigs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ScanRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScanRecordsTable> {
  $$ScanRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get goal =>
      $composableBuilder(column: $table.goal, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get imagePath =>
      $composableBuilder(column: $table.imagePath, builder: (column) => column);

  GeneratedColumn<String> get failureCode => $composableBuilder(
    column: $table.failureCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get failureMessage => $composableBuilder(
    column: $table.failureMessage,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<String> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  $$PigsTableAnnotationComposer get pigId {
    final $$PigsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.pigId,
      referencedTable: $db.pigs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PigsTableAnnotationComposer(
            $db: $db,
            $table: $db.pigs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> referenceAnnotationsRefs<T extends Object>(
    Expression<T> Function($$ReferenceAnnotationsTableAnnotationComposer a) f,
  ) {
    final $$ReferenceAnnotationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.referenceAnnotations,
          getReferencedColumn: (t) => t.scanId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReferenceAnnotationsTableAnnotationComposer(
                $db: $db,
                $table: $db.referenceAnnotations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> weightResultsRefs<T extends Object>(
    Expression<T> Function($$WeightResultsTableAnnotationComposer a) f,
  ) {
    final $$WeightResultsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.weightResults,
      getReferencedColumn: (t) => t.scanId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WeightResultsTableAnnotationComposer(
            $db: $db,
            $table: $db.weightResults,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> healthResultsRefs<T extends Object>(
    Expression<T> Function($$HealthResultsTableAnnotationComposer a) f,
  ) {
    final $$HealthResultsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.healthResults,
      getReferencedColumn: (t) => t.scanId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$HealthResultsTableAnnotationComposer(
            $db: $db,
            $table: $db.healthResults,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> pipelineEventsRefs<T extends Object>(
    Expression<T> Function($$PipelineEventsTableAnnotationComposer a) f,
  ) {
    final $$PipelineEventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.pipelineEvents,
      getReferencedColumn: (t) => t.scanId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PipelineEventsTableAnnotationComposer(
            $db: $db,
            $table: $db.pipelineEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ScanRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScanRecordsTable,
          ScanRecord,
          $$ScanRecordsTableFilterComposer,
          $$ScanRecordsTableOrderingComposer,
          $$ScanRecordsTableAnnotationComposer,
          $$ScanRecordsTableCreateCompanionBuilder,
          $$ScanRecordsTableUpdateCompanionBuilder,
          (ScanRecord, $$ScanRecordsTableReferences),
          ScanRecord,
          PrefetchHooks Function({
            bool pigId,
            bool referenceAnnotationsRefs,
            bool weightResultsRefs,
            bool healthResultsRefs,
            bool pipelineEventsRefs,
          })
        > {
  $$ScanRecordsTableTableManager(_$AppDatabase db, $ScanRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScanRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScanRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScanRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> pigId = const Value.absent(),
                Value<String> goal = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                Value<String?> failureMessage = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime?> capturedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<String?> remoteId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScanRecordsCompanion(
                id: id,
                pigId: pigId,
                goal: goal,
                status: status,
                imagePath: imagePath,
                failureCode: failureCode,
                failureMessage: failureMessage,
                notes: notes,
                capturedAt: capturedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncState: syncState,
                remoteId: remoteId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> pigId = const Value.absent(),
                required String goal,
                Value<String> status = const Value.absent(),
                Value<String?> imagePath = const Value.absent(),
                Value<String?> failureCode = const Value.absent(),
                Value<String?> failureMessage = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime?> capturedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<String?> remoteId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScanRecordsCompanion.insert(
                id: id,
                pigId: pigId,
                goal: goal,
                status: status,
                imagePath: imagePath,
                failureCode: failureCode,
                failureMessage: failureMessage,
                notes: notes,
                capturedAt: capturedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncState: syncState,
                remoteId: remoteId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ScanRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                pigId = false,
                referenceAnnotationsRefs = false,
                weightResultsRefs = false,
                healthResultsRefs = false,
                pipelineEventsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (referenceAnnotationsRefs) db.referenceAnnotations,
                    if (weightResultsRefs) db.weightResults,
                    if (healthResultsRefs) db.healthResults,
                    if (pipelineEventsRefs) db.pipelineEvents,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (pigId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.pigId,
                                    referencedTable:
                                        $$ScanRecordsTableReferences
                                            ._pigIdTable(db),
                                    referencedColumn:
                                        $$ScanRecordsTableReferences
                                            ._pigIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (referenceAnnotationsRefs)
                        await $_getPrefetchedData<
                          ScanRecord,
                          $ScanRecordsTable,
                          ReferenceAnnotation
                        >(
                          currentTable: table,
                          referencedTable: $$ScanRecordsTableReferences
                              ._referenceAnnotationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ScanRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).referenceAnnotationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.scanId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (weightResultsRefs)
                        await $_getPrefetchedData<
                          ScanRecord,
                          $ScanRecordsTable,
                          WeightResult
                        >(
                          currentTable: table,
                          referencedTable: $$ScanRecordsTableReferences
                              ._weightResultsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ScanRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).weightResultsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.scanId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (healthResultsRefs)
                        await $_getPrefetchedData<
                          ScanRecord,
                          $ScanRecordsTable,
                          HealthResult
                        >(
                          currentTable: table,
                          referencedTable: $$ScanRecordsTableReferences
                              ._healthResultsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ScanRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).healthResultsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.scanId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (pipelineEventsRefs)
                        await $_getPrefetchedData<
                          ScanRecord,
                          $ScanRecordsTable,
                          PipelineEvent
                        >(
                          currentTable: table,
                          referencedTable: $$ScanRecordsTableReferences
                              ._pipelineEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ScanRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).pipelineEventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.scanId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ScanRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScanRecordsTable,
      ScanRecord,
      $$ScanRecordsTableFilterComposer,
      $$ScanRecordsTableOrderingComposer,
      $$ScanRecordsTableAnnotationComposer,
      $$ScanRecordsTableCreateCompanionBuilder,
      $$ScanRecordsTableUpdateCompanionBuilder,
      (ScanRecord, $$ScanRecordsTableReferences),
      ScanRecord,
      PrefetchHooks Function({
        bool pigId,
        bool referenceAnnotationsRefs,
        bool weightResultsRefs,
        bool healthResultsRefs,
        bool pipelineEventsRefs,
      })
    >;
typedef $$ReferenceAnnotationsTableCreateCompanionBuilder =
    ReferenceAnnotationsCompanion Function({
      required String scanId,
      required String objectType,
      required String objectName,
      required double lengthCm,
      Value<double?> startX,
      Value<double?> startY,
      Value<double?> endX,
      Value<double?> endY,
      Value<double?> pixelLength,
      Value<double?> cmPerPixel,
      Value<String> source,
      Value<double?> detectorConfidence,
      Value<bool> userConfirmed,
      Value<bool> sameFloorPlaneConfirmed,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ReferenceAnnotationsTableUpdateCompanionBuilder =
    ReferenceAnnotationsCompanion Function({
      Value<String> scanId,
      Value<String> objectType,
      Value<String> objectName,
      Value<double> lengthCm,
      Value<double?> startX,
      Value<double?> startY,
      Value<double?> endX,
      Value<double?> endY,
      Value<double?> pixelLength,
      Value<double?> cmPerPixel,
      Value<String> source,
      Value<double?> detectorConfidence,
      Value<bool> userConfirmed,
      Value<bool> sameFloorPlaneConfirmed,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$ReferenceAnnotationsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ReferenceAnnotationsTable,
          ReferenceAnnotation
        > {
  $$ReferenceAnnotationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ScanRecordsTable _scanIdTable(_$AppDatabase db) =>
      db.scanRecords.createAlias(
        $_aliasNameGenerator(db.referenceAnnotations.scanId, db.scanRecords.id),
      );

  $$ScanRecordsTableProcessedTableManager get scanId {
    final $_column = $_itemColumn<String>('scan_id')!;

    final manager = $$ScanRecordsTableTableManager(
      $_db,
      $_db.scanRecords,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_scanIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReferenceAnnotationsTableFilterComposer
    extends Composer<_$AppDatabase, $ReferenceAnnotationsTable> {
  $$ReferenceAnnotationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get objectType => $composableBuilder(
    column: $table.objectType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get objectName => $composableBuilder(
    column: $table.objectName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lengthCm => $composableBuilder(
    column: $table.lengthCm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get startX => $composableBuilder(
    column: $table.startX,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get startY => $composableBuilder(
    column: $table.startY,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get endX => $composableBuilder(
    column: $table.endX,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get endY => $composableBuilder(
    column: $table.endY,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pixelLength => $composableBuilder(
    column: $table.pixelLength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cmPerPixel => $composableBuilder(
    column: $table.cmPerPixel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get detectorConfidence => $composableBuilder(
    column: $table.detectorConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get userConfirmed => $composableBuilder(
    column: $table.userConfirmed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get sameFloorPlaneConfirmed => $composableBuilder(
    column: $table.sameFloorPlaneConfirmed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ScanRecordsTableFilterComposer get scanId {
    final $$ScanRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.scanId,
      referencedTable: $db.scanRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanRecordsTableFilterComposer(
            $db: $db,
            $table: $db.scanRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReferenceAnnotationsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReferenceAnnotationsTable> {
  $$ReferenceAnnotationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get objectType => $composableBuilder(
    column: $table.objectType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get objectName => $composableBuilder(
    column: $table.objectName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lengthCm => $composableBuilder(
    column: $table.lengthCm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get startX => $composableBuilder(
    column: $table.startX,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get startY => $composableBuilder(
    column: $table.startY,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get endX => $composableBuilder(
    column: $table.endX,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get endY => $composableBuilder(
    column: $table.endY,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pixelLength => $composableBuilder(
    column: $table.pixelLength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cmPerPixel => $composableBuilder(
    column: $table.cmPerPixel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get detectorConfidence => $composableBuilder(
    column: $table.detectorConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get userConfirmed => $composableBuilder(
    column: $table.userConfirmed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get sameFloorPlaneConfirmed => $composableBuilder(
    column: $table.sameFloorPlaneConfirmed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ScanRecordsTableOrderingComposer get scanId {
    final $$ScanRecordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.scanId,
      referencedTable: $db.scanRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanRecordsTableOrderingComposer(
            $db: $db,
            $table: $db.scanRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReferenceAnnotationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReferenceAnnotationsTable> {
  $$ReferenceAnnotationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get objectType => $composableBuilder(
    column: $table.objectType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get objectName => $composableBuilder(
    column: $table.objectName,
    builder: (column) => column,
  );

  GeneratedColumn<double> get lengthCm =>
      $composableBuilder(column: $table.lengthCm, builder: (column) => column);

  GeneratedColumn<double> get startX =>
      $composableBuilder(column: $table.startX, builder: (column) => column);

  GeneratedColumn<double> get startY =>
      $composableBuilder(column: $table.startY, builder: (column) => column);

  GeneratedColumn<double> get endX =>
      $composableBuilder(column: $table.endX, builder: (column) => column);

  GeneratedColumn<double> get endY =>
      $composableBuilder(column: $table.endY, builder: (column) => column);

  GeneratedColumn<double> get pixelLength => $composableBuilder(
    column: $table.pixelLength,
    builder: (column) => column,
  );

  GeneratedColumn<double> get cmPerPixel => $composableBuilder(
    column: $table.cmPerPixel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<double> get detectorConfidence => $composableBuilder(
    column: $table.detectorConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get userConfirmed => $composableBuilder(
    column: $table.userConfirmed,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get sameFloorPlaneConfirmed => $composableBuilder(
    column: $table.sameFloorPlaneConfirmed,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$ScanRecordsTableAnnotationComposer get scanId {
    final $$ScanRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.scanId,
      referencedTable: $db.scanRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.scanRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReferenceAnnotationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReferenceAnnotationsTable,
          ReferenceAnnotation,
          $$ReferenceAnnotationsTableFilterComposer,
          $$ReferenceAnnotationsTableOrderingComposer,
          $$ReferenceAnnotationsTableAnnotationComposer,
          $$ReferenceAnnotationsTableCreateCompanionBuilder,
          $$ReferenceAnnotationsTableUpdateCompanionBuilder,
          (ReferenceAnnotation, $$ReferenceAnnotationsTableReferences),
          ReferenceAnnotation,
          PrefetchHooks Function({bool scanId})
        > {
  $$ReferenceAnnotationsTableTableManager(
    _$AppDatabase db,
    $ReferenceAnnotationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReferenceAnnotationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReferenceAnnotationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ReferenceAnnotationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> scanId = const Value.absent(),
                Value<String> objectType = const Value.absent(),
                Value<String> objectName = const Value.absent(),
                Value<double> lengthCm = const Value.absent(),
                Value<double?> startX = const Value.absent(),
                Value<double?> startY = const Value.absent(),
                Value<double?> endX = const Value.absent(),
                Value<double?> endY = const Value.absent(),
                Value<double?> pixelLength = const Value.absent(),
                Value<double?> cmPerPixel = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<double?> detectorConfidence = const Value.absent(),
                Value<bool> userConfirmed = const Value.absent(),
                Value<bool> sameFloorPlaneConfirmed = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReferenceAnnotationsCompanion(
                scanId: scanId,
                objectType: objectType,
                objectName: objectName,
                lengthCm: lengthCm,
                startX: startX,
                startY: startY,
                endX: endX,
                endY: endY,
                pixelLength: pixelLength,
                cmPerPixel: cmPerPixel,
                source: source,
                detectorConfidence: detectorConfidence,
                userConfirmed: userConfirmed,
                sameFloorPlaneConfirmed: sameFloorPlaneConfirmed,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String scanId,
                required String objectType,
                required String objectName,
                required double lengthCm,
                Value<double?> startX = const Value.absent(),
                Value<double?> startY = const Value.absent(),
                Value<double?> endX = const Value.absent(),
                Value<double?> endY = const Value.absent(),
                Value<double?> pixelLength = const Value.absent(),
                Value<double?> cmPerPixel = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<double?> detectorConfidence = const Value.absent(),
                Value<bool> userConfirmed = const Value.absent(),
                Value<bool> sameFloorPlaneConfirmed = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReferenceAnnotationsCompanion.insert(
                scanId: scanId,
                objectType: objectType,
                objectName: objectName,
                lengthCm: lengthCm,
                startX: startX,
                startY: startY,
                endX: endX,
                endY: endY,
                pixelLength: pixelLength,
                cmPerPixel: cmPerPixel,
                source: source,
                detectorConfidence: detectorConfidence,
                userConfirmed: userConfirmed,
                sameFloorPlaneConfirmed: sameFloorPlaneConfirmed,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReferenceAnnotationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({scanId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (scanId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.scanId,
                                referencedTable:
                                    $$ReferenceAnnotationsTableReferences
                                        ._scanIdTable(db),
                                referencedColumn:
                                    $$ReferenceAnnotationsTableReferences
                                        ._scanIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReferenceAnnotationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReferenceAnnotationsTable,
      ReferenceAnnotation,
      $$ReferenceAnnotationsTableFilterComposer,
      $$ReferenceAnnotationsTableOrderingComposer,
      $$ReferenceAnnotationsTableAnnotationComposer,
      $$ReferenceAnnotationsTableCreateCompanionBuilder,
      $$ReferenceAnnotationsTableUpdateCompanionBuilder,
      (ReferenceAnnotation, $$ReferenceAnnotationsTableReferences),
      ReferenceAnnotation,
      PrefetchHooks Function({bool scanId})
    >;
typedef $$WeightResultsTableCreateCompanionBuilder =
    WeightResultsCompanion Function({
      required String scanId,
      required bool eligible,
      Value<double?> valueKg,
      Value<double?> referenceLengthCm,
      Value<double?> referencePixelLength,
      Value<double?> cmPerPixel,
      Value<double?> featureRa,
      Value<double?> featureLc,
      Value<double?> featureBl,
      Value<double?> featureBw,
      Value<double?> featureE,
      Value<String?> failureReason,
      Value<String?> modelVersion,
      Value<String?> preprocessingVersion,
      Value<String?> thresholdVersion,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$WeightResultsTableUpdateCompanionBuilder =
    WeightResultsCompanion Function({
      Value<String> scanId,
      Value<bool> eligible,
      Value<double?> valueKg,
      Value<double?> referenceLengthCm,
      Value<double?> referencePixelLength,
      Value<double?> cmPerPixel,
      Value<double?> featureRa,
      Value<double?> featureLc,
      Value<double?> featureBl,
      Value<double?> featureBw,
      Value<double?> featureE,
      Value<String?> failureReason,
      Value<String?> modelVersion,
      Value<String?> preprocessingVersion,
      Value<String?> thresholdVersion,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$WeightResultsTableReferences
    extends BaseReferences<_$AppDatabase, $WeightResultsTable, WeightResult> {
  $$WeightResultsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ScanRecordsTable _scanIdTable(_$AppDatabase db) =>
      db.scanRecords.createAlias(
        $_aliasNameGenerator(db.weightResults.scanId, db.scanRecords.id),
      );

  $$ScanRecordsTableProcessedTableManager get scanId {
    final $_column = $_itemColumn<String>('scan_id')!;

    final manager = $$ScanRecordsTableTableManager(
      $_db,
      $_db.scanRecords,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_scanIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$WeightResultsTableFilterComposer
    extends Composer<_$AppDatabase, $WeightResultsTable> {
  $$WeightResultsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get eligible => $composableBuilder(
    column: $table.eligible,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get valueKg => $composableBuilder(
    column: $table.valueKg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get referenceLengthCm => $composableBuilder(
    column: $table.referenceLengthCm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get referencePixelLength => $composableBuilder(
    column: $table.referencePixelLength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cmPerPixel => $composableBuilder(
    column: $table.cmPerPixel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get featureRa => $composableBuilder(
    column: $table.featureRa,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get featureLc => $composableBuilder(
    column: $table.featureLc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get featureBl => $composableBuilder(
    column: $table.featureBl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get featureBw => $composableBuilder(
    column: $table.featureBw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get featureE => $composableBuilder(
    column: $table.featureE,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelVersion => $composableBuilder(
    column: $table.modelVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get preprocessingVersion => $composableBuilder(
    column: $table.preprocessingVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thresholdVersion => $composableBuilder(
    column: $table.thresholdVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ScanRecordsTableFilterComposer get scanId {
    final $$ScanRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.scanId,
      referencedTable: $db.scanRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanRecordsTableFilterComposer(
            $db: $db,
            $table: $db.scanRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WeightResultsTableOrderingComposer
    extends Composer<_$AppDatabase, $WeightResultsTable> {
  $$WeightResultsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get eligible => $composableBuilder(
    column: $table.eligible,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get valueKg => $composableBuilder(
    column: $table.valueKg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get referenceLengthCm => $composableBuilder(
    column: $table.referenceLengthCm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get referencePixelLength => $composableBuilder(
    column: $table.referencePixelLength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cmPerPixel => $composableBuilder(
    column: $table.cmPerPixel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get featureRa => $composableBuilder(
    column: $table.featureRa,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get featureLc => $composableBuilder(
    column: $table.featureLc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get featureBl => $composableBuilder(
    column: $table.featureBl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get featureBw => $composableBuilder(
    column: $table.featureBw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get featureE => $composableBuilder(
    column: $table.featureE,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelVersion => $composableBuilder(
    column: $table.modelVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get preprocessingVersion => $composableBuilder(
    column: $table.preprocessingVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thresholdVersion => $composableBuilder(
    column: $table.thresholdVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ScanRecordsTableOrderingComposer get scanId {
    final $$ScanRecordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.scanId,
      referencedTable: $db.scanRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanRecordsTableOrderingComposer(
            $db: $db,
            $table: $db.scanRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WeightResultsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WeightResultsTable> {
  $$WeightResultsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get eligible =>
      $composableBuilder(column: $table.eligible, builder: (column) => column);

  GeneratedColumn<double> get valueKg =>
      $composableBuilder(column: $table.valueKg, builder: (column) => column);

  GeneratedColumn<double> get referenceLengthCm => $composableBuilder(
    column: $table.referenceLengthCm,
    builder: (column) => column,
  );

  GeneratedColumn<double> get referencePixelLength => $composableBuilder(
    column: $table.referencePixelLength,
    builder: (column) => column,
  );

  GeneratedColumn<double> get cmPerPixel => $composableBuilder(
    column: $table.cmPerPixel,
    builder: (column) => column,
  );

  GeneratedColumn<double> get featureRa =>
      $composableBuilder(column: $table.featureRa, builder: (column) => column);

  GeneratedColumn<double> get featureLc =>
      $composableBuilder(column: $table.featureLc, builder: (column) => column);

  GeneratedColumn<double> get featureBl =>
      $composableBuilder(column: $table.featureBl, builder: (column) => column);

  GeneratedColumn<double> get featureBw =>
      $composableBuilder(column: $table.featureBw, builder: (column) => column);

  GeneratedColumn<double> get featureE =>
      $composableBuilder(column: $table.featureE, builder: (column) => column);

  GeneratedColumn<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get modelVersion => $composableBuilder(
    column: $table.modelVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get preprocessingVersion => $composableBuilder(
    column: $table.preprocessingVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thresholdVersion => $composableBuilder(
    column: $table.thresholdVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ScanRecordsTableAnnotationComposer get scanId {
    final $$ScanRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.scanId,
      referencedTable: $db.scanRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.scanRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WeightResultsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WeightResultsTable,
          WeightResult,
          $$WeightResultsTableFilterComposer,
          $$WeightResultsTableOrderingComposer,
          $$WeightResultsTableAnnotationComposer,
          $$WeightResultsTableCreateCompanionBuilder,
          $$WeightResultsTableUpdateCompanionBuilder,
          (WeightResult, $$WeightResultsTableReferences),
          WeightResult,
          PrefetchHooks Function({bool scanId})
        > {
  $$WeightResultsTableTableManager(_$AppDatabase db, $WeightResultsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WeightResultsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WeightResultsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WeightResultsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> scanId = const Value.absent(),
                Value<bool> eligible = const Value.absent(),
                Value<double?> valueKg = const Value.absent(),
                Value<double?> referenceLengthCm = const Value.absent(),
                Value<double?> referencePixelLength = const Value.absent(),
                Value<double?> cmPerPixel = const Value.absent(),
                Value<double?> featureRa = const Value.absent(),
                Value<double?> featureLc = const Value.absent(),
                Value<double?> featureBl = const Value.absent(),
                Value<double?> featureBw = const Value.absent(),
                Value<double?> featureE = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<String?> modelVersion = const Value.absent(),
                Value<String?> preprocessingVersion = const Value.absent(),
                Value<String?> thresholdVersion = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WeightResultsCompanion(
                scanId: scanId,
                eligible: eligible,
                valueKg: valueKg,
                referenceLengthCm: referenceLengthCm,
                referencePixelLength: referencePixelLength,
                cmPerPixel: cmPerPixel,
                featureRa: featureRa,
                featureLc: featureLc,
                featureBl: featureBl,
                featureBw: featureBw,
                featureE: featureE,
                failureReason: failureReason,
                modelVersion: modelVersion,
                preprocessingVersion: preprocessingVersion,
                thresholdVersion: thresholdVersion,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String scanId,
                required bool eligible,
                Value<double?> valueKg = const Value.absent(),
                Value<double?> referenceLengthCm = const Value.absent(),
                Value<double?> referencePixelLength = const Value.absent(),
                Value<double?> cmPerPixel = const Value.absent(),
                Value<double?> featureRa = const Value.absent(),
                Value<double?> featureLc = const Value.absent(),
                Value<double?> featureBl = const Value.absent(),
                Value<double?> featureBw = const Value.absent(),
                Value<double?> featureE = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<String?> modelVersion = const Value.absent(),
                Value<String?> preprocessingVersion = const Value.absent(),
                Value<String?> thresholdVersion = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WeightResultsCompanion.insert(
                scanId: scanId,
                eligible: eligible,
                valueKg: valueKg,
                referenceLengthCm: referenceLengthCm,
                referencePixelLength: referencePixelLength,
                cmPerPixel: cmPerPixel,
                featureRa: featureRa,
                featureLc: featureLc,
                featureBl: featureBl,
                featureBw: featureBw,
                featureE: featureE,
                failureReason: failureReason,
                modelVersion: modelVersion,
                preprocessingVersion: preprocessingVersion,
                thresholdVersion: thresholdVersion,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$WeightResultsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({scanId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (scanId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.scanId,
                                referencedTable: $$WeightResultsTableReferences
                                    ._scanIdTable(db),
                                referencedColumn: $$WeightResultsTableReferences
                                    ._scanIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$WeightResultsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WeightResultsTable,
      WeightResult,
      $$WeightResultsTableFilterComposer,
      $$WeightResultsTableOrderingComposer,
      $$WeightResultsTableAnnotationComposer,
      $$WeightResultsTableCreateCompanionBuilder,
      $$WeightResultsTableUpdateCompanionBuilder,
      (WeightResult, $$WeightResultsTableReferences),
      WeightResult,
      PrefetchHooks Function({bool scanId})
    >;
typedef $$HealthResultsTableCreateCompanionBuilder =
    HealthResultsCompanion Function({
      required String scanId,
      required bool eligible,
      Value<String?> className,
      Value<double?> confidence,
      Value<bool> uncertain,
      Value<String?> failureReason,
      Value<String?> modelVersion,
      Value<String?> preprocessingVersion,
      Value<String?> thresholdVersion,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$HealthResultsTableUpdateCompanionBuilder =
    HealthResultsCompanion Function({
      Value<String> scanId,
      Value<bool> eligible,
      Value<String?> className,
      Value<double?> confidence,
      Value<bool> uncertain,
      Value<String?> failureReason,
      Value<String?> modelVersion,
      Value<String?> preprocessingVersion,
      Value<String?> thresholdVersion,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$HealthResultsTableReferences
    extends BaseReferences<_$AppDatabase, $HealthResultsTable, HealthResult> {
  $$HealthResultsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ScanRecordsTable _scanIdTable(_$AppDatabase db) =>
      db.scanRecords.createAlias(
        $_aliasNameGenerator(db.healthResults.scanId, db.scanRecords.id),
      );

  $$ScanRecordsTableProcessedTableManager get scanId {
    final $_column = $_itemColumn<String>('scan_id')!;

    final manager = $$ScanRecordsTableTableManager(
      $_db,
      $_db.scanRecords,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_scanIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$HealthResultsTableFilterComposer
    extends Composer<_$AppDatabase, $HealthResultsTable> {
  $$HealthResultsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get eligible => $composableBuilder(
    column: $table.eligible,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get className => $composableBuilder(
    column: $table.className,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get uncertain => $composableBuilder(
    column: $table.uncertain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelVersion => $composableBuilder(
    column: $table.modelVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get preprocessingVersion => $composableBuilder(
    column: $table.preprocessingVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thresholdVersion => $composableBuilder(
    column: $table.thresholdVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ScanRecordsTableFilterComposer get scanId {
    final $$ScanRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.scanId,
      referencedTable: $db.scanRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanRecordsTableFilterComposer(
            $db: $db,
            $table: $db.scanRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HealthResultsTableOrderingComposer
    extends Composer<_$AppDatabase, $HealthResultsTable> {
  $$HealthResultsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get eligible => $composableBuilder(
    column: $table.eligible,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get className => $composableBuilder(
    column: $table.className,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get uncertain => $composableBuilder(
    column: $table.uncertain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelVersion => $composableBuilder(
    column: $table.modelVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get preprocessingVersion => $composableBuilder(
    column: $table.preprocessingVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thresholdVersion => $composableBuilder(
    column: $table.thresholdVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ScanRecordsTableOrderingComposer get scanId {
    final $$ScanRecordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.scanId,
      referencedTable: $db.scanRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanRecordsTableOrderingComposer(
            $db: $db,
            $table: $db.scanRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HealthResultsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HealthResultsTable> {
  $$HealthResultsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get eligible =>
      $composableBuilder(column: $table.eligible, builder: (column) => column);

  GeneratedColumn<String> get className =>
      $composableBuilder(column: $table.className, builder: (column) => column);

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get uncertain =>
      $composableBuilder(column: $table.uncertain, builder: (column) => column);

  GeneratedColumn<String> get failureReason => $composableBuilder(
    column: $table.failureReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get modelVersion => $composableBuilder(
    column: $table.modelVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get preprocessingVersion => $composableBuilder(
    column: $table.preprocessingVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thresholdVersion => $composableBuilder(
    column: $table.thresholdVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ScanRecordsTableAnnotationComposer get scanId {
    final $$ScanRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.scanId,
      referencedTable: $db.scanRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.scanRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$HealthResultsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HealthResultsTable,
          HealthResult,
          $$HealthResultsTableFilterComposer,
          $$HealthResultsTableOrderingComposer,
          $$HealthResultsTableAnnotationComposer,
          $$HealthResultsTableCreateCompanionBuilder,
          $$HealthResultsTableUpdateCompanionBuilder,
          (HealthResult, $$HealthResultsTableReferences),
          HealthResult,
          PrefetchHooks Function({bool scanId})
        > {
  $$HealthResultsTableTableManager(_$AppDatabase db, $HealthResultsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HealthResultsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HealthResultsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HealthResultsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> scanId = const Value.absent(),
                Value<bool> eligible = const Value.absent(),
                Value<String?> className = const Value.absent(),
                Value<double?> confidence = const Value.absent(),
                Value<bool> uncertain = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<String?> modelVersion = const Value.absent(),
                Value<String?> preprocessingVersion = const Value.absent(),
                Value<String?> thresholdVersion = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HealthResultsCompanion(
                scanId: scanId,
                eligible: eligible,
                className: className,
                confidence: confidence,
                uncertain: uncertain,
                failureReason: failureReason,
                modelVersion: modelVersion,
                preprocessingVersion: preprocessingVersion,
                thresholdVersion: thresholdVersion,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String scanId,
                required bool eligible,
                Value<String?> className = const Value.absent(),
                Value<double?> confidence = const Value.absent(),
                Value<bool> uncertain = const Value.absent(),
                Value<String?> failureReason = const Value.absent(),
                Value<String?> modelVersion = const Value.absent(),
                Value<String?> preprocessingVersion = const Value.absent(),
                Value<String?> thresholdVersion = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HealthResultsCompanion.insert(
                scanId: scanId,
                eligible: eligible,
                className: className,
                confidence: confidence,
                uncertain: uncertain,
                failureReason: failureReason,
                modelVersion: modelVersion,
                preprocessingVersion: preprocessingVersion,
                thresholdVersion: thresholdVersion,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$HealthResultsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({scanId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (scanId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.scanId,
                                referencedTable: $$HealthResultsTableReferences
                                    ._scanIdTable(db),
                                referencedColumn: $$HealthResultsTableReferences
                                    ._scanIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$HealthResultsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HealthResultsTable,
      HealthResult,
      $$HealthResultsTableFilterComposer,
      $$HealthResultsTableOrderingComposer,
      $$HealthResultsTableAnnotationComposer,
      $$HealthResultsTableCreateCompanionBuilder,
      $$HealthResultsTableUpdateCompanionBuilder,
      (HealthResult, $$HealthResultsTableReferences),
      HealthResult,
      PrefetchHooks Function({bool scanId})
    >;
typedef $$PipelineEventsTableCreateCompanionBuilder =
    PipelineEventsCompanion Function({
      Value<int> id,
      required String scanId,
      required String stage,
      required String status,
      Value<String?> message,
      Value<DateTime> createdAt,
    });
typedef $$PipelineEventsTableUpdateCompanionBuilder =
    PipelineEventsCompanion Function({
      Value<int> id,
      Value<String> scanId,
      Value<String> stage,
      Value<String> status,
      Value<String?> message,
      Value<DateTime> createdAt,
    });

final class $$PipelineEventsTableReferences
    extends BaseReferences<_$AppDatabase, $PipelineEventsTable, PipelineEvent> {
  $$PipelineEventsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ScanRecordsTable _scanIdTable(_$AppDatabase db) =>
      db.scanRecords.createAlias(
        $_aliasNameGenerator(db.pipelineEvents.scanId, db.scanRecords.id),
      );

  $$ScanRecordsTableProcessedTableManager get scanId {
    final $_column = $_itemColumn<String>('scan_id')!;

    final manager = $$ScanRecordsTableTableManager(
      $_db,
      $_db.scanRecords,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_scanIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PipelineEventsTableFilterComposer
    extends Composer<_$AppDatabase, $PipelineEventsTable> {
  $$PipelineEventsTableFilterComposer({
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

  ColumnFilters<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ScanRecordsTableFilterComposer get scanId {
    final $$ScanRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.scanId,
      referencedTable: $db.scanRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanRecordsTableFilterComposer(
            $db: $db,
            $table: $db.scanRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PipelineEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $PipelineEventsTable> {
  $$PipelineEventsTableOrderingComposer({
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

  ColumnOrderings<String> get stage => $composableBuilder(
    column: $table.stage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ScanRecordsTableOrderingComposer get scanId {
    final $$ScanRecordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.scanId,
      referencedTable: $db.scanRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanRecordsTableOrderingComposer(
            $db: $db,
            $table: $db.scanRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PipelineEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PipelineEventsTable> {
  $$PipelineEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get stage =>
      $composableBuilder(column: $table.stage, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ScanRecordsTableAnnotationComposer get scanId {
    final $$ScanRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.scanId,
      referencedTable: $db.scanRecords,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ScanRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.scanRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PipelineEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PipelineEventsTable,
          PipelineEvent,
          $$PipelineEventsTableFilterComposer,
          $$PipelineEventsTableOrderingComposer,
          $$PipelineEventsTableAnnotationComposer,
          $$PipelineEventsTableCreateCompanionBuilder,
          $$PipelineEventsTableUpdateCompanionBuilder,
          (PipelineEvent, $$PipelineEventsTableReferences),
          PipelineEvent,
          PrefetchHooks Function({bool scanId})
        > {
  $$PipelineEventsTableTableManager(
    _$AppDatabase db,
    $PipelineEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PipelineEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PipelineEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PipelineEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> scanId = const Value.absent(),
                Value<String> stage = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> message = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => PipelineEventsCompanion(
                id: id,
                scanId: scanId,
                stage: stage,
                status: status,
                message: message,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String scanId,
                required String stage,
                required String status,
                Value<String?> message = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => PipelineEventsCompanion.insert(
                id: id,
                scanId: scanId,
                stage: stage,
                status: status,
                message: message,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PipelineEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({scanId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (scanId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.scanId,
                                referencedTable: $$PipelineEventsTableReferences
                                    ._scanIdTable(db),
                                referencedColumn:
                                    $$PipelineEventsTableReferences
                                        ._scanIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PipelineEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PipelineEventsTable,
      PipelineEvent,
      $$PipelineEventsTableFilterComposer,
      $$PipelineEventsTableOrderingComposer,
      $$PipelineEventsTableAnnotationComposer,
      $$PipelineEventsTableCreateCompanionBuilder,
      $$PipelineEventsTableUpdateCompanionBuilder,
      (PipelineEvent, $$PipelineEventsTableReferences),
      PipelineEvent,
      PrefetchHooks Function({bool scanId})
    >;
typedef $$PrivacyPreferencesTableCreateCompanionBuilder =
    PrivacyPreferencesCompanion Function({
      Value<int> id,
      Value<bool> researchImageSharing,
      Value<bool> usageAnalytics,
      Value<String> inferenceMode,
      Value<int?> retentionDays,
      Value<DateTime> updatedAt,
    });
typedef $$PrivacyPreferencesTableUpdateCompanionBuilder =
    PrivacyPreferencesCompanion Function({
      Value<int> id,
      Value<bool> researchImageSharing,
      Value<bool> usageAnalytics,
      Value<String> inferenceMode,
      Value<int?> retentionDays,
      Value<DateTime> updatedAt,
    });

class $$PrivacyPreferencesTableFilterComposer
    extends Composer<_$AppDatabase, $PrivacyPreferencesTable> {
  $$PrivacyPreferencesTableFilterComposer({
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

  ColumnFilters<bool> get researchImageSharing => $composableBuilder(
    column: $table.researchImageSharing,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get usageAnalytics => $composableBuilder(
    column: $table.usageAnalytics,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inferenceMode => $composableBuilder(
    column: $table.inferenceMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retentionDays => $composableBuilder(
    column: $table.retentionDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PrivacyPreferencesTableOrderingComposer
    extends Composer<_$AppDatabase, $PrivacyPreferencesTable> {
  $$PrivacyPreferencesTableOrderingComposer({
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

  ColumnOrderings<bool> get researchImageSharing => $composableBuilder(
    column: $table.researchImageSharing,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get usageAnalytics => $composableBuilder(
    column: $table.usageAnalytics,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inferenceMode => $composableBuilder(
    column: $table.inferenceMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retentionDays => $composableBuilder(
    column: $table.retentionDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PrivacyPreferencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PrivacyPreferencesTable> {
  $$PrivacyPreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get researchImageSharing => $composableBuilder(
    column: $table.researchImageSharing,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get usageAnalytics => $composableBuilder(
    column: $table.usageAnalytics,
    builder: (column) => column,
  );

  GeneratedColumn<String> get inferenceMode => $composableBuilder(
    column: $table.inferenceMode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get retentionDays => $composableBuilder(
    column: $table.retentionDays,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PrivacyPreferencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PrivacyPreferencesTable,
          PrivacyPreference,
          $$PrivacyPreferencesTableFilterComposer,
          $$PrivacyPreferencesTableOrderingComposer,
          $$PrivacyPreferencesTableAnnotationComposer,
          $$PrivacyPreferencesTableCreateCompanionBuilder,
          $$PrivacyPreferencesTableUpdateCompanionBuilder,
          (
            PrivacyPreference,
            BaseReferences<
              _$AppDatabase,
              $PrivacyPreferencesTable,
              PrivacyPreference
            >,
          ),
          PrivacyPreference,
          PrefetchHooks Function()
        > {
  $$PrivacyPreferencesTableTableManager(
    _$AppDatabase db,
    $PrivacyPreferencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PrivacyPreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PrivacyPreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PrivacyPreferencesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<bool> researchImageSharing = const Value.absent(),
                Value<bool> usageAnalytics = const Value.absent(),
                Value<String> inferenceMode = const Value.absent(),
                Value<int?> retentionDays = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => PrivacyPreferencesCompanion(
                id: id,
                researchImageSharing: researchImageSharing,
                usageAnalytics: usageAnalytics,
                inferenceMode: inferenceMode,
                retentionDays: retentionDays,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<bool> researchImageSharing = const Value.absent(),
                Value<bool> usageAnalytics = const Value.absent(),
                Value<String> inferenceMode = const Value.absent(),
                Value<int?> retentionDays = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => PrivacyPreferencesCompanion.insert(
                id: id,
                researchImageSharing: researchImageSharing,
                usageAnalytics: usageAnalytics,
                inferenceMode: inferenceMode,
                retentionDays: retentionDays,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PrivacyPreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PrivacyPreferencesTable,
      PrivacyPreference,
      $$PrivacyPreferencesTableFilterComposer,
      $$PrivacyPreferencesTableOrderingComposer,
      $$PrivacyPreferencesTableAnnotationComposer,
      $$PrivacyPreferencesTableCreateCompanionBuilder,
      $$PrivacyPreferencesTableUpdateCompanionBuilder,
      (
        PrivacyPreference,
        BaseReferences<
          _$AppDatabase,
          $PrivacyPreferencesTable,
          PrivacyPreference
        >,
      ),
      PrivacyPreference,
      PrefetchHooks Function()
    >;
typedef $$SyncOutboxEntriesTableCreateCompanionBuilder =
    SyncOutboxEntriesCompanion Function({
      Value<int> id,
      required String entityType,
      required String entityId,
      required String operation,
      required String payloadJson,
      Value<String> state,
      Value<int> attempts,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$SyncOutboxEntriesTableUpdateCompanionBuilder =
    SyncOutboxEntriesCompanion Function({
      Value<int> id,
      Value<String> entityType,
      Value<String> entityId,
      Value<String> operation,
      Value<String> payloadJson,
      Value<String> state,
      Value<int> attempts,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$SyncOutboxEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $SyncOutboxEntriesTable> {
  $$SyncOutboxEntriesTableFilterComposer({
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

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOutboxEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncOutboxEntriesTable> {
  $$SyncOutboxEntriesTableOrderingComposer({
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

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOutboxEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncOutboxEntriesTable> {
  $$SyncOutboxEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncOutboxEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncOutboxEntriesTable,
          SyncOutboxEntry,
          $$SyncOutboxEntriesTableFilterComposer,
          $$SyncOutboxEntriesTableOrderingComposer,
          $$SyncOutboxEntriesTableAnnotationComposer,
          $$SyncOutboxEntriesTableCreateCompanionBuilder,
          $$SyncOutboxEntriesTableUpdateCompanionBuilder,
          (
            SyncOutboxEntry,
            BaseReferences<
              _$AppDatabase,
              $SyncOutboxEntriesTable,
              SyncOutboxEntry
            >,
          ),
          SyncOutboxEntry,
          PrefetchHooks Function()
        > {
  $$SyncOutboxEntriesTableTableManager(
    _$AppDatabase db,
    $SyncOutboxEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOutboxEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOutboxEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOutboxEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => SyncOutboxEntriesCompanion(
                id: id,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                payloadJson: payloadJson,
                state: state,
                attempts: attempts,
                lastError: lastError,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String entityType,
                required String entityId,
                required String operation,
                required String payloadJson,
                Value<String> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => SyncOutboxEntriesCompanion.insert(
                id: id,
                entityType: entityType,
                entityId: entityId,
                operation: operation,
                payloadJson: payloadJson,
                state: state,
                attempts: attempts,
                lastError: lastError,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOutboxEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncOutboxEntriesTable,
      SyncOutboxEntry,
      $$SyncOutboxEntriesTableFilterComposer,
      $$SyncOutboxEntriesTableOrderingComposer,
      $$SyncOutboxEntriesTableAnnotationComposer,
      $$SyncOutboxEntriesTableCreateCompanionBuilder,
      $$SyncOutboxEntriesTableUpdateCompanionBuilder,
      (
        SyncOutboxEntry,
        BaseReferences<_$AppDatabase, $SyncOutboxEntriesTable, SyncOutboxEntry>,
      ),
      SyncOutboxEntry,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PigsTableTableManager get pigs => $$PigsTableTableManager(_db, _db.pigs);
  $$ScanRecordsTableTableManager get scanRecords =>
      $$ScanRecordsTableTableManager(_db, _db.scanRecords);
  $$ReferenceAnnotationsTableTableManager get referenceAnnotations =>
      $$ReferenceAnnotationsTableTableManager(_db, _db.referenceAnnotations);
  $$WeightResultsTableTableManager get weightResults =>
      $$WeightResultsTableTableManager(_db, _db.weightResults);
  $$HealthResultsTableTableManager get healthResults =>
      $$HealthResultsTableTableManager(_db, _db.healthResults);
  $$PipelineEventsTableTableManager get pipelineEvents =>
      $$PipelineEventsTableTableManager(_db, _db.pipelineEvents);
  $$PrivacyPreferencesTableTableManager get privacyPreferences =>
      $$PrivacyPreferencesTableTableManager(_db, _db.privacyPreferences);
  $$SyncOutboxEntriesTableTableManager get syncOutboxEntries =>
      $$SyncOutboxEntriesTableTableManager(_db, _db.syncOutboxEntries);
}
