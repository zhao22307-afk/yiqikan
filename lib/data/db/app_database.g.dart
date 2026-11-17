// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $RoomsTable extends Rooms with TableInfo<$RoomsTable, Room> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoomsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _joinUrlMeta = const VerificationMeta(
    'joinUrl',
  );
  @override
  late final GeneratedColumn<String> joinUrl = GeneratedColumn<String>(
    'join_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hostNameMeta = const VerificationMeta(
    'hostName',
  );
  @override
  late final GeneratedColumn<String> hostName = GeneratedColumn<String>(
    'host_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _passwordHashMeta = const VerificationMeta(
    'passwordHash',
  );
  @override
  late final GeneratedColumn<String> passwordHash = GeneratedColumn<String>(
    'password_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<int> isFavorite = GeneratedColumn<int>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _memberCountMeta = const VerificationMeta(
    'memberCount',
  );
  @override
  late final GeneratedColumn<int> memberCount = GeneratedColumn<int>(
    'member_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastJoinedAtMeta = const VerificationMeta(
    'lastJoinedAt',
  );
  @override
  late final GeneratedColumn<int> lastJoinedAt = GeneratedColumn<int>(
    'last_joined_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _extraMeta = const VerificationMeta('extra');
  @override
  late final GeneratedColumn<String> extra = GeneratedColumn<String>(
    'extra',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    code,
    mode,
    joinUrl,
    hostName,
    passwordHash,
    isFavorite,
    memberCount,
    lastJoinedAt,
    createdAt,
    extra,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rooms';
  @override
  VerificationContext validateIntegrity(
    Insertable<Room> instance, {
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
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('join_url')) {
      context.handle(
        _joinUrlMeta,
        joinUrl.isAcceptableOrUnknown(data['join_url']!, _joinUrlMeta),
      );
    }
    if (data.containsKey('host_name')) {
      context.handle(
        _hostNameMeta,
        hostName.isAcceptableOrUnknown(data['host_name']!, _hostNameMeta),
      );
    }
    if (data.containsKey('password_hash')) {
      context.handle(
        _passwordHashMeta,
        passwordHash.isAcceptableOrUnknown(
          data['password_hash']!,
          _passwordHashMeta,
        ),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('member_count')) {
      context.handle(
        _memberCountMeta,
        memberCount.isAcceptableOrUnknown(
          data['member_count']!,
          _memberCountMeta,
        ),
      );
    }
    if (data.containsKey('last_joined_at')) {
      context.handle(
        _lastJoinedAtMeta,
        lastJoinedAt.isAcceptableOrUnknown(
          data['last_joined_at']!,
          _lastJoinedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastJoinedAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('extra')) {
      context.handle(
        _extraMeta,
        extra.isAcceptableOrUnknown(data['extra']!, _extraMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Room map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Room(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      joinUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}join_url'],
      ),
      hostName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_name'],
      ),
      passwordHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}password_hash'],
      ),
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_favorite'],
      )!,
      memberCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}member_count'],
      )!,
      lastJoinedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_joined_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      extra: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extra'],
      ),
    );
  }

  @override
  $RoomsTable createAlias(String alias) {
    return $RoomsTable(attachedDatabase, alias);
  }
}

class Room extends DataClass implements Insertable<Room> {
  /// 'r_abc123'
  final String id;

  /// 房间名
  final String name;

  /// 6 位数字房间号
  final String code;

  /// lan/direct/cloud/backend/embedded/tunnel/mesh
  final String mode;

  /// 上次可用地址（可能已失效，失败再重算）
  final String? joinUrl;

  /// 房主昵称
  final String? hostName;

  /// 口令 sha256（固定盐）
  final String? passwordHash;

  /// 0/1
  final int isFavorite;
  final int memberCount;

  /// 毫秒时间戳
  final int lastJoinedAt;
  final int createdAt;

  /// JSON 扩展（房间背景 / 公告等）
  final String? extra;
  const Room({
    required this.id,
    required this.name,
    required this.code,
    required this.mode,
    this.joinUrl,
    this.hostName,
    this.passwordHash,
    required this.isFavorite,
    required this.memberCount,
    required this.lastJoinedAt,
    required this.createdAt,
    this.extra,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['code'] = Variable<String>(code);
    map['mode'] = Variable<String>(mode);
    if (!nullToAbsent || joinUrl != null) {
      map['join_url'] = Variable<String>(joinUrl);
    }
    if (!nullToAbsent || hostName != null) {
      map['host_name'] = Variable<String>(hostName);
    }
    if (!nullToAbsent || passwordHash != null) {
      map['password_hash'] = Variable<String>(passwordHash);
    }
    map['is_favorite'] = Variable<int>(isFavorite);
    map['member_count'] = Variable<int>(memberCount);
    map['last_joined_at'] = Variable<int>(lastJoinedAt);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || extra != null) {
      map['extra'] = Variable<String>(extra);
    }
    return map;
  }

  RoomsCompanion toCompanion(bool nullToAbsent) {
    return RoomsCompanion(
      id: Value(id),
      name: Value(name),
      code: Value(code),
      mode: Value(mode),
      joinUrl: joinUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(joinUrl),
      hostName: hostName == null && nullToAbsent
          ? const Value.absent()
          : Value(hostName),
      passwordHash: passwordHash == null && nullToAbsent
          ? const Value.absent()
          : Value(passwordHash),
      isFavorite: Value(isFavorite),
      memberCount: Value(memberCount),
      lastJoinedAt: Value(lastJoinedAt),
      createdAt: Value(createdAt),
      extra: extra == null && nullToAbsent
          ? const Value.absent()
          : Value(extra),
    );
  }

  factory Room.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Room(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      code: serializer.fromJson<String>(json['code']),
      mode: serializer.fromJson<String>(json['mode']),
      joinUrl: serializer.fromJson<String?>(json['joinUrl']),
      hostName: serializer.fromJson<String?>(json['hostName']),
      passwordHash: serializer.fromJson<String?>(json['passwordHash']),
      isFavorite: serializer.fromJson<int>(json['isFavorite']),
      memberCount: serializer.fromJson<int>(json['memberCount']),
      lastJoinedAt: serializer.fromJson<int>(json['lastJoinedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      extra: serializer.fromJson<String?>(json['extra']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'code': serializer.toJson<String>(code),
      'mode': serializer.toJson<String>(mode),
      'joinUrl': serializer.toJson<String?>(joinUrl),
      'hostName': serializer.toJson<String?>(hostName),
      'passwordHash': serializer.toJson<String?>(passwordHash),
      'isFavorite': serializer.toJson<int>(isFavorite),
      'memberCount': serializer.toJson<int>(memberCount),
      'lastJoinedAt': serializer.toJson<int>(lastJoinedAt),
      'createdAt': serializer.toJson<int>(createdAt),
      'extra': serializer.toJson<String?>(extra),
    };
  }

  Room copyWith({
    String? id,
    String? name,
    String? code,
    String? mode,
    Value<String?> joinUrl = const Value.absent(),
    Value<String?> hostName = const Value.absent(),
    Value<String?> passwordHash = const Value.absent(),
    int? isFavorite,
    int? memberCount,
    int? lastJoinedAt,
    int? createdAt,
    Value<String?> extra = const Value.absent(),
  }) => Room(
    id: id ?? this.id,
    name: name ?? this.name,
    code: code ?? this.code,
    mode: mode ?? this.mode,
    joinUrl: joinUrl.present ? joinUrl.value : this.joinUrl,
    hostName: hostName.present ? hostName.value : this.hostName,
    passwordHash: passwordHash.present ? passwordHash.value : this.passwordHash,
    isFavorite: isFavorite ?? this.isFavorite,
    memberCount: memberCount ?? this.memberCount,
    lastJoinedAt: lastJoinedAt ?? this.lastJoinedAt,
    createdAt: createdAt ?? this.createdAt,
    extra: extra.present ? extra.value : this.extra,
  );
  Room copyWithCompanion(RoomsCompanion data) {
    return Room(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      code: data.code.present ? data.code.value : this.code,
      mode: data.mode.present ? data.mode.value : this.mode,
      joinUrl: data.joinUrl.present ? data.joinUrl.value : this.joinUrl,
      hostName: data.hostName.present ? data.hostName.value : this.hostName,
      passwordHash: data.passwordHash.present
          ? data.passwordHash.value
          : this.passwordHash,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      memberCount: data.memberCount.present
          ? data.memberCount.value
          : this.memberCount,
      lastJoinedAt: data.lastJoinedAt.present
          ? data.lastJoinedAt.value
          : this.lastJoinedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      extra: data.extra.present ? data.extra.value : this.extra,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Room(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('code: $code, ')
          ..write('mode: $mode, ')
          ..write('joinUrl: $joinUrl, ')
          ..write('hostName: $hostName, ')
          ..write('passwordHash: $passwordHash, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('memberCount: $memberCount, ')
          ..write('lastJoinedAt: $lastJoinedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('extra: $extra')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    code,
    mode,
    joinUrl,
    hostName,
    passwordHash,
    isFavorite,
    memberCount,
    lastJoinedAt,
    createdAt,
    extra,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Room &&
          other.id == this.id &&
          other.name == this.name &&
          other.code == this.code &&
          other.mode == this.mode &&
          other.joinUrl == this.joinUrl &&
          other.hostName == this.hostName &&
          other.passwordHash == this.passwordHash &&
          other.isFavorite == this.isFavorite &&
          other.memberCount == this.memberCount &&
          other.lastJoinedAt == this.lastJoinedAt &&
          other.createdAt == this.createdAt &&
          other.extra == this.extra);
}

class RoomsCompanion extends UpdateCompanion<Room> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> code;
  final Value<String> mode;
  final Value<String?> joinUrl;
  final Value<String?> hostName;
  final Value<String?> passwordHash;
  final Value<int> isFavorite;
  final Value<int> memberCount;
  final Value<int> lastJoinedAt;
  final Value<int> createdAt;
  final Value<String?> extra;
  final Value<int> rowid;
  const RoomsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.code = const Value.absent(),
    this.mode = const Value.absent(),
    this.joinUrl = const Value.absent(),
    this.hostName = const Value.absent(),
    this.passwordHash = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.memberCount = const Value.absent(),
    this.lastJoinedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RoomsCompanion.insert({
    required String id,
    required String name,
    required String code,
    required String mode,
    this.joinUrl = const Value.absent(),
    this.hostName = const Value.absent(),
    this.passwordHash = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.memberCount = const Value.absent(),
    required int lastJoinedAt,
    required int createdAt,
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       code = Value(code),
       mode = Value(mode),
       lastJoinedAt = Value(lastJoinedAt),
       createdAt = Value(createdAt);
  static Insertable<Room> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? code,
    Expression<String>? mode,
    Expression<String>? joinUrl,
    Expression<String>? hostName,
    Expression<String>? passwordHash,
    Expression<int>? isFavorite,
    Expression<int>? memberCount,
    Expression<int>? lastJoinedAt,
    Expression<int>? createdAt,
    Expression<String>? extra,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (code != null) 'code': code,
      if (mode != null) 'mode': mode,
      if (joinUrl != null) 'join_url': joinUrl,
      if (hostName != null) 'host_name': hostName,
      if (passwordHash != null) 'password_hash': passwordHash,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (memberCount != null) 'member_count': memberCount,
      if (lastJoinedAt != null) 'last_joined_at': lastJoinedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (extra != null) 'extra': extra,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RoomsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? code,
    Value<String>? mode,
    Value<String?>? joinUrl,
    Value<String?>? hostName,
    Value<String?>? passwordHash,
    Value<int>? isFavorite,
    Value<int>? memberCount,
    Value<int>? lastJoinedAt,
    Value<int>? createdAt,
    Value<String?>? extra,
    Value<int>? rowid,
  }) {
    return RoomsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      mode: mode ?? this.mode,
      joinUrl: joinUrl ?? this.joinUrl,
      hostName: hostName ?? this.hostName,
      passwordHash: passwordHash ?? this.passwordHash,
      isFavorite: isFavorite ?? this.isFavorite,
      memberCount: memberCount ?? this.memberCount,
      lastJoinedAt: lastJoinedAt ?? this.lastJoinedAt,
      createdAt: createdAt ?? this.createdAt,
      extra: extra ?? this.extra,
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
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (joinUrl.present) {
      map['join_url'] = Variable<String>(joinUrl.value);
    }
    if (hostName.present) {
      map['host_name'] = Variable<String>(hostName.value);
    }
    if (passwordHash.present) {
      map['password_hash'] = Variable<String>(passwordHash.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<int>(isFavorite.value);
    }
    if (memberCount.present) {
      map['member_count'] = Variable<int>(memberCount.value);
    }
    if (lastJoinedAt.present) {
      map['last_joined_at'] = Variable<int>(lastJoinedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (extra.present) {
      map['extra'] = Variable<String>(extra.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoomsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('code: $code, ')
          ..write('mode: $mode, ')
          ..write('joinUrl: $joinUrl, ')
          ..write('hostName: $hostName, ')
          ..write('passwordHash: $passwordHash, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('memberCount: $memberCount, ')
          ..write('lastJoinedAt: $lastJoinedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('extra: $extra, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HistoryTableTable extends HistoryTable
    with TableInfo<$HistoryTableTable, History> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoryTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceKindMeta = const VerificationMeta(
    'sourceKind',
  );
  @override
  late final GeneratedColumn<String> sourceKind = GeneratedColumn<String>(
    'source_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _posterMeta = const VerificationMeta('poster');
  @override
  late final GeneratedColumn<String> poster = GeneratedColumn<String>(
    'poster',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<double> position = GeneratedColumn<double>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationMeta = const VerificationMeta(
    'duration',
  );
  @override
  late final GeneratedColumn<double> duration = GeneratedColumn<double>(
    'duration',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _watchedSecondsMeta = const VerificationMeta(
    'watchedSeconds',
  );
  @override
  late final GeneratedColumn<int> watchedSeconds = GeneratedColumn<int>(
    'watched_seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _episodeIndexMeta = const VerificationMeta(
    'episodeIndex',
  );
  @override
  late final GeneratedColumn<int> episodeIndex = GeneratedColumn<int>(
    'episode_index',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<String> seriesId = GeneratedColumn<String>(
    'series_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _watchedAtMeta = const VerificationMeta(
    'watchedAt',
  );
  @override
  late final GeneratedColumn<int> watchedAt = GeneratedColumn<int>(
    'watched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _extraMeta = const VerificationMeta('extra');
  @override
  late final GeneratedColumn<String> extra = GeneratedColumn<String>(
    'extra',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    url,
    sourceKind,
    sourceId,
    poster,
    position,
    duration,
    watchedSeconds,
    episodeIndex,
    seriesId,
    watchedAt,
    createdAt,
    extra,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'history';
  @override
  VerificationContext validateIntegrity(
    Insertable<History> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('source_kind')) {
      context.handle(
        _sourceKindMeta,
        sourceKind.isAcceptableOrUnknown(data['source_kind']!, _sourceKindMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceKindMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('poster')) {
      context.handle(
        _posterMeta,
        poster.isAcceptableOrUnknown(data['poster']!, _posterMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    if (data.containsKey('duration')) {
      context.handle(
        _durationMeta,
        duration.isAcceptableOrUnknown(data['duration']!, _durationMeta),
      );
    }
    if (data.containsKey('watched_seconds')) {
      context.handle(
        _watchedSecondsMeta,
        watchedSeconds.isAcceptableOrUnknown(
          data['watched_seconds']!,
          _watchedSecondsMeta,
        ),
      );
    }
    if (data.containsKey('episode_index')) {
      context.handle(
        _episodeIndexMeta,
        episodeIndex.isAcceptableOrUnknown(
          data['episode_index']!,
          _episodeIndexMeta,
        ),
      );
    }
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    }
    if (data.containsKey('watched_at')) {
      context.handle(
        _watchedAtMeta,
        watchedAt.isAcceptableOrUnknown(data['watched_at']!, _watchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_watchedAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('extra')) {
      context.handle(
        _extraMeta,
        extra.isAcceptableOrUnknown(data['extra']!, _extraMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  History map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return History(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      sourceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_kind'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      ),
      poster: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poster'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}position'],
      )!,
      duration: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}duration'],
      )!,
      watchedSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}watched_seconds'],
      )!,
      episodeIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode_index'],
      ),
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      ),
      watchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}watched_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      extra: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extra'],
      ),
    );
  }

  @override
  $HistoryTableTable createAlias(String alias) {
    return $HistoryTableTable(attachedDatabase, alias);
  }
}

class History extends DataClass implements Insertable<History> {
  /// 用 media url 的 md5 前 16 位
  final String id;
  final String title;
  final String url;

  /// direct/bilibili/quark/emby/webdav/alist/maccms
  final String sourceKind;

  /// 该源内的 id（bvid / fid / itemId）
  final String? sourceId;
  final String? poster;

  /// 秒
  final double position;

  /// 秒
  final double duration;

  /// 累计观看秒数（增量累加 clamp(0,60)，不是等于 position）
  final int watchedSeconds;

  /// 第几集（0 开始）
  final int? episodeIndex;

  /// 所属剧集 id（同剧不同集共享）
  final String? seriesId;

  /// 最后观看时间（毫秒）
  final int watchedAt;
  final int createdAt;
  final String? extra;
  const History({
    required this.id,
    required this.title,
    required this.url,
    required this.sourceKind,
    this.sourceId,
    this.poster,
    required this.position,
    required this.duration,
    required this.watchedSeconds,
    this.episodeIndex,
    this.seriesId,
    required this.watchedAt,
    required this.createdAt,
    this.extra,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['url'] = Variable<String>(url);
    map['source_kind'] = Variable<String>(sourceKind);
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<String>(sourceId);
    }
    if (!nullToAbsent || poster != null) {
      map['poster'] = Variable<String>(poster);
    }
    map['position'] = Variable<double>(position);
    map['duration'] = Variable<double>(duration);
    map['watched_seconds'] = Variable<int>(watchedSeconds);
    if (!nullToAbsent || episodeIndex != null) {
      map['episode_index'] = Variable<int>(episodeIndex);
    }
    if (!nullToAbsent || seriesId != null) {
      map['series_id'] = Variable<String>(seriesId);
    }
    map['watched_at'] = Variable<int>(watchedAt);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || extra != null) {
      map['extra'] = Variable<String>(extra);
    }
    return map;
  }

  HistoryTableCompanion toCompanion(bool nullToAbsent) {
    return HistoryTableCompanion(
      id: Value(id),
      title: Value(title),
      url: Value(url),
      sourceKind: Value(sourceKind),
      sourceId: sourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceId),
      poster: poster == null && nullToAbsent
          ? const Value.absent()
          : Value(poster),
      position: Value(position),
      duration: Value(duration),
      watchedSeconds: Value(watchedSeconds),
      episodeIndex: episodeIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(episodeIndex),
      seriesId: seriesId == null && nullToAbsent
          ? const Value.absent()
          : Value(seriesId),
      watchedAt: Value(watchedAt),
      createdAt: Value(createdAt),
      extra: extra == null && nullToAbsent
          ? const Value.absent()
          : Value(extra),
    );
  }

  factory History.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return History(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      url: serializer.fromJson<String>(json['url']),
      sourceKind: serializer.fromJson<String>(json['sourceKind']),
      sourceId: serializer.fromJson<String?>(json['sourceId']),
      poster: serializer.fromJson<String?>(json['poster']),
      position: serializer.fromJson<double>(json['position']),
      duration: serializer.fromJson<double>(json['duration']),
      watchedSeconds: serializer.fromJson<int>(json['watchedSeconds']),
      episodeIndex: serializer.fromJson<int?>(json['episodeIndex']),
      seriesId: serializer.fromJson<String?>(json['seriesId']),
      watchedAt: serializer.fromJson<int>(json['watchedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      extra: serializer.fromJson<String?>(json['extra']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'url': serializer.toJson<String>(url),
      'sourceKind': serializer.toJson<String>(sourceKind),
      'sourceId': serializer.toJson<String?>(sourceId),
      'poster': serializer.toJson<String?>(poster),
      'position': serializer.toJson<double>(position),
      'duration': serializer.toJson<double>(duration),
      'watchedSeconds': serializer.toJson<int>(watchedSeconds),
      'episodeIndex': serializer.toJson<int?>(episodeIndex),
      'seriesId': serializer.toJson<String?>(seriesId),
      'watchedAt': serializer.toJson<int>(watchedAt),
      'createdAt': serializer.toJson<int>(createdAt),
      'extra': serializer.toJson<String?>(extra),
    };
  }

  History copyWith({
    String? id,
    String? title,
    String? url,
    String? sourceKind,
    Value<String?> sourceId = const Value.absent(),
    Value<String?> poster = const Value.absent(),
    double? position,
    double? duration,
    int? watchedSeconds,
    Value<int?> episodeIndex = const Value.absent(),
    Value<String?> seriesId = const Value.absent(),
    int? watchedAt,
    int? createdAt,
    Value<String?> extra = const Value.absent(),
  }) => History(
    id: id ?? this.id,
    title: title ?? this.title,
    url: url ?? this.url,
    sourceKind: sourceKind ?? this.sourceKind,
    sourceId: sourceId.present ? sourceId.value : this.sourceId,
    poster: poster.present ? poster.value : this.poster,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    watchedSeconds: watchedSeconds ?? this.watchedSeconds,
    episodeIndex: episodeIndex.present ? episodeIndex.value : this.episodeIndex,
    seriesId: seriesId.present ? seriesId.value : this.seriesId,
    watchedAt: watchedAt ?? this.watchedAt,
    createdAt: createdAt ?? this.createdAt,
    extra: extra.present ? extra.value : this.extra,
  );
  History copyWithCompanion(HistoryTableCompanion data) {
    return History(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      url: data.url.present ? data.url.value : this.url,
      sourceKind: data.sourceKind.present
          ? data.sourceKind.value
          : this.sourceKind,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      poster: data.poster.present ? data.poster.value : this.poster,
      position: data.position.present ? data.position.value : this.position,
      duration: data.duration.present ? data.duration.value : this.duration,
      watchedSeconds: data.watchedSeconds.present
          ? data.watchedSeconds.value
          : this.watchedSeconds,
      episodeIndex: data.episodeIndex.present
          ? data.episodeIndex.value
          : this.episodeIndex,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      watchedAt: data.watchedAt.present ? data.watchedAt.value : this.watchedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      extra: data.extra.present ? data.extra.value : this.extra,
    );
  }

  @override
  String toString() {
    return (StringBuffer('History(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('url: $url, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceId: $sourceId, ')
          ..write('poster: $poster, ')
          ..write('position: $position, ')
          ..write('duration: $duration, ')
          ..write('watchedSeconds: $watchedSeconds, ')
          ..write('episodeIndex: $episodeIndex, ')
          ..write('seriesId: $seriesId, ')
          ..write('watchedAt: $watchedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('extra: $extra')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    url,
    sourceKind,
    sourceId,
    poster,
    position,
    duration,
    watchedSeconds,
    episodeIndex,
    seriesId,
    watchedAt,
    createdAt,
    extra,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is History &&
          other.id == this.id &&
          other.title == this.title &&
          other.url == this.url &&
          other.sourceKind == this.sourceKind &&
          other.sourceId == this.sourceId &&
          other.poster == this.poster &&
          other.position == this.position &&
          other.duration == this.duration &&
          other.watchedSeconds == this.watchedSeconds &&
          other.episodeIndex == this.episodeIndex &&
          other.seriesId == this.seriesId &&
          other.watchedAt == this.watchedAt &&
          other.createdAt == this.createdAt &&
          other.extra == this.extra);
}

class HistoryTableCompanion extends UpdateCompanion<History> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> url;
  final Value<String> sourceKind;
  final Value<String?> sourceId;
  final Value<String?> poster;
  final Value<double> position;
  final Value<double> duration;
  final Value<int> watchedSeconds;
  final Value<int?> episodeIndex;
  final Value<String?> seriesId;
  final Value<int> watchedAt;
  final Value<int> createdAt;
  final Value<String?> extra;
  final Value<int> rowid;
  const HistoryTableCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.url = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.poster = const Value.absent(),
    this.position = const Value.absent(),
    this.duration = const Value.absent(),
    this.watchedSeconds = const Value.absent(),
    this.episodeIndex = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.watchedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HistoryTableCompanion.insert({
    required String id,
    required String title,
    required String url,
    required String sourceKind,
    this.sourceId = const Value.absent(),
    this.poster = const Value.absent(),
    this.position = const Value.absent(),
    this.duration = const Value.absent(),
    this.watchedSeconds = const Value.absent(),
    this.episodeIndex = const Value.absent(),
    this.seriesId = const Value.absent(),
    required int watchedAt,
    required int createdAt,
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       url = Value(url),
       sourceKind = Value(sourceKind),
       watchedAt = Value(watchedAt),
       createdAt = Value(createdAt);
  static Insertable<History> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? url,
    Expression<String>? sourceKind,
    Expression<String>? sourceId,
    Expression<String>? poster,
    Expression<double>? position,
    Expression<double>? duration,
    Expression<int>? watchedSeconds,
    Expression<int>? episodeIndex,
    Expression<String>? seriesId,
    Expression<int>? watchedAt,
    Expression<int>? createdAt,
    Expression<String>? extra,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (url != null) 'url': url,
      if (sourceKind != null) 'source_kind': sourceKind,
      if (sourceId != null) 'source_id': sourceId,
      if (poster != null) 'poster': poster,
      if (position != null) 'position': position,
      if (duration != null) 'duration': duration,
      if (watchedSeconds != null) 'watched_seconds': watchedSeconds,
      if (episodeIndex != null) 'episode_index': episodeIndex,
      if (seriesId != null) 'series_id': seriesId,
      if (watchedAt != null) 'watched_at': watchedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (extra != null) 'extra': extra,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HistoryTableCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? url,
    Value<String>? sourceKind,
    Value<String?>? sourceId,
    Value<String?>? poster,
    Value<double>? position,
    Value<double>? duration,
    Value<int>? watchedSeconds,
    Value<int?>? episodeIndex,
    Value<String?>? seriesId,
    Value<int>? watchedAt,
    Value<int>? createdAt,
    Value<String?>? extra,
    Value<int>? rowid,
  }) {
    return HistoryTableCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      sourceKind: sourceKind ?? this.sourceKind,
      sourceId: sourceId ?? this.sourceId,
      poster: poster ?? this.poster,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      watchedSeconds: watchedSeconds ?? this.watchedSeconds,
      episodeIndex: episodeIndex ?? this.episodeIndex,
      seriesId: seriesId ?? this.seriesId,
      watchedAt: watchedAt ?? this.watchedAt,
      createdAt: createdAt ?? this.createdAt,
      extra: extra ?? this.extra,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (sourceKind.present) {
      map['source_kind'] = Variable<String>(sourceKind.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (poster.present) {
      map['poster'] = Variable<String>(poster.value);
    }
    if (position.present) {
      map['position'] = Variable<double>(position.value);
    }
    if (duration.present) {
      map['duration'] = Variable<double>(duration.value);
    }
    if (watchedSeconds.present) {
      map['watched_seconds'] = Variable<int>(watchedSeconds.value);
    }
    if (episodeIndex.present) {
      map['episode_index'] = Variable<int>(episodeIndex.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
    }
    if (watchedAt.present) {
      map['watched_at'] = Variable<int>(watchedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (extra.present) {
      map['extra'] = Variable<String>(extra.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryTableCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('url: $url, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceId: $sourceId, ')
          ..write('poster: $poster, ')
          ..write('position: $position, ')
          ..write('duration: $duration, ')
          ..write('watchedSeconds: $watchedSeconds, ')
          ..write('episodeIndex: $episodeIndex, ')
          ..write('seriesId: $seriesId, ')
          ..write('watchedAt: $watchedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('extra: $extra, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FavoritesTable extends Favorites
    with TableInfo<$FavoritesTable, Favorite> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoritesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceKindMeta = const VerificationMeta(
    'sourceKind',
  );
  @override
  late final GeneratedColumn<String> sourceKind = GeneratedColumn<String>(
    'source_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _posterMeta = const VerificationMeta('poster');
  @override
  late final GeneratedColumn<String> poster = GeneratedColumn<String>(
    'poster',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tagMeta = const VerificationMeta('tag');
  @override
  late final GeneratedColumn<String> tag = GeneratedColumn<String>(
    'tag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _extraMeta = const VerificationMeta('extra');
  @override
  late final GeneratedColumn<String> extra = GeneratedColumn<String>(
    'extra',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    url,
    sourceKind,
    sourceId,
    poster,
    tag,
    note,
    addedAt,
    extra,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorites';
  @override
  VerificationContext validateIntegrity(
    Insertable<Favorite> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('source_kind')) {
      context.handle(
        _sourceKindMeta,
        sourceKind.isAcceptableOrUnknown(data['source_kind']!, _sourceKindMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceKindMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('poster')) {
      context.handle(
        _posterMeta,
        poster.isAcceptableOrUnknown(data['poster']!, _posterMeta),
      );
    }
    if (data.containsKey('tag')) {
      context.handle(
        _tagMeta,
        tag.isAcceptableOrUnknown(data['tag']!, _tagMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
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
    if (data.containsKey('extra')) {
      context.handle(
        _extraMeta,
        extra.isAcceptableOrUnknown(data['extra']!, _extraMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Favorite map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Favorite(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      sourceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_kind'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      ),
      poster: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poster'],
      ),
      tag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
      extra: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extra'],
      ),
    );
  }

  @override
  $FavoritesTable createAlias(String alias) {
    return $FavoritesTable(attachedDatabase, alias);
  }
}

class Favorite extends DataClass implements Insertable<Favorite> {
  final String id;
  final String title;
  final String url;
  final String sourceKind;
  final String? sourceId;
  final String? poster;

  /// 用户自定义分组
  final String? tag;

  /// 备注
  final String? note;
  final int addedAt;
  final String? extra;
  const Favorite({
    required this.id,
    required this.title,
    required this.url,
    required this.sourceKind,
    this.sourceId,
    this.poster,
    this.tag,
    this.note,
    required this.addedAt,
    this.extra,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['url'] = Variable<String>(url);
    map['source_kind'] = Variable<String>(sourceKind);
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<String>(sourceId);
    }
    if (!nullToAbsent || poster != null) {
      map['poster'] = Variable<String>(poster);
    }
    if (!nullToAbsent || tag != null) {
      map['tag'] = Variable<String>(tag);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['added_at'] = Variable<int>(addedAt);
    if (!nullToAbsent || extra != null) {
      map['extra'] = Variable<String>(extra);
    }
    return map;
  }

  FavoritesCompanion toCompanion(bool nullToAbsent) {
    return FavoritesCompanion(
      id: Value(id),
      title: Value(title),
      url: Value(url),
      sourceKind: Value(sourceKind),
      sourceId: sourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceId),
      poster: poster == null && nullToAbsent
          ? const Value.absent()
          : Value(poster),
      tag: tag == null && nullToAbsent ? const Value.absent() : Value(tag),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      addedAt: Value(addedAt),
      extra: extra == null && nullToAbsent
          ? const Value.absent()
          : Value(extra),
    );
  }

  factory Favorite.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Favorite(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      url: serializer.fromJson<String>(json['url']),
      sourceKind: serializer.fromJson<String>(json['sourceKind']),
      sourceId: serializer.fromJson<String?>(json['sourceId']),
      poster: serializer.fromJson<String?>(json['poster']),
      tag: serializer.fromJson<String?>(json['tag']),
      note: serializer.fromJson<String?>(json['note']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
      extra: serializer.fromJson<String?>(json['extra']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'url': serializer.toJson<String>(url),
      'sourceKind': serializer.toJson<String>(sourceKind),
      'sourceId': serializer.toJson<String?>(sourceId),
      'poster': serializer.toJson<String?>(poster),
      'tag': serializer.toJson<String?>(tag),
      'note': serializer.toJson<String?>(note),
      'addedAt': serializer.toJson<int>(addedAt),
      'extra': serializer.toJson<String?>(extra),
    };
  }

  Favorite copyWith({
    String? id,
    String? title,
    String? url,
    String? sourceKind,
    Value<String?> sourceId = const Value.absent(),
    Value<String?> poster = const Value.absent(),
    Value<String?> tag = const Value.absent(),
    Value<String?> note = const Value.absent(),
    int? addedAt,
    Value<String?> extra = const Value.absent(),
  }) => Favorite(
    id: id ?? this.id,
    title: title ?? this.title,
    url: url ?? this.url,
    sourceKind: sourceKind ?? this.sourceKind,
    sourceId: sourceId.present ? sourceId.value : this.sourceId,
    poster: poster.present ? poster.value : this.poster,
    tag: tag.present ? tag.value : this.tag,
    note: note.present ? note.value : this.note,
    addedAt: addedAt ?? this.addedAt,
    extra: extra.present ? extra.value : this.extra,
  );
  Favorite copyWithCompanion(FavoritesCompanion data) {
    return Favorite(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      url: data.url.present ? data.url.value : this.url,
      sourceKind: data.sourceKind.present
          ? data.sourceKind.value
          : this.sourceKind,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      poster: data.poster.present ? data.poster.value : this.poster,
      tag: data.tag.present ? data.tag.value : this.tag,
      note: data.note.present ? data.note.value : this.note,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      extra: data.extra.present ? data.extra.value : this.extra,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Favorite(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('url: $url, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceId: $sourceId, ')
          ..write('poster: $poster, ')
          ..write('tag: $tag, ')
          ..write('note: $note, ')
          ..write('addedAt: $addedAt, ')
          ..write('extra: $extra')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    url,
    sourceKind,
    sourceId,
    poster,
    tag,
    note,
    addedAt,
    extra,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Favorite &&
          other.id == this.id &&
          other.title == this.title &&
          other.url == this.url &&
          other.sourceKind == this.sourceKind &&
          other.sourceId == this.sourceId &&
          other.poster == this.poster &&
          other.tag == this.tag &&
          other.note == this.note &&
          other.addedAt == this.addedAt &&
          other.extra == this.extra);
}

class FavoritesCompanion extends UpdateCompanion<Favorite> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> url;
  final Value<String> sourceKind;
  final Value<String?> sourceId;
  final Value<String?> poster;
  final Value<String?> tag;
  final Value<String?> note;
  final Value<int> addedAt;
  final Value<String?> extra;
  final Value<int> rowid;
  const FavoritesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.url = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.poster = const Value.absent(),
    this.tag = const Value.absent(),
    this.note = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoritesCompanion.insert({
    required String id,
    required String title,
    required String url,
    required String sourceKind,
    this.sourceId = const Value.absent(),
    this.poster = const Value.absent(),
    this.tag = const Value.absent(),
    this.note = const Value.absent(),
    required int addedAt,
    this.extra = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       url = Value(url),
       sourceKind = Value(sourceKind),
       addedAt = Value(addedAt);
  static Insertable<Favorite> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? url,
    Expression<String>? sourceKind,
    Expression<String>? sourceId,
    Expression<String>? poster,
    Expression<String>? tag,
    Expression<String>? note,
    Expression<int>? addedAt,
    Expression<String>? extra,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (url != null) 'url': url,
      if (sourceKind != null) 'source_kind': sourceKind,
      if (sourceId != null) 'source_id': sourceId,
      if (poster != null) 'poster': poster,
      if (tag != null) 'tag': tag,
      if (note != null) 'note': note,
      if (addedAt != null) 'added_at': addedAt,
      if (extra != null) 'extra': extra,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoritesCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? url,
    Value<String>? sourceKind,
    Value<String?>? sourceId,
    Value<String?>? poster,
    Value<String?>? tag,
    Value<String?>? note,
    Value<int>? addedAt,
    Value<String?>? extra,
    Value<int>? rowid,
  }) {
    return FavoritesCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      sourceKind: sourceKind ?? this.sourceKind,
      sourceId: sourceId ?? this.sourceId,
      poster: poster ?? this.poster,
      tag: tag ?? this.tag,
      note: note ?? this.note,
      addedAt: addedAt ?? this.addedAt,
      extra: extra ?? this.extra,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (sourceKind.present) {
      map['source_kind'] = Variable<String>(sourceKind.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (poster.present) {
      map['poster'] = Variable<String>(poster.value);
    }
    if (tag.present) {
      map['tag'] = Variable<String>(tag.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (extra.present) {
      map['extra'] = Variable<String>(extra.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoritesCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('url: $url, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceId: $sourceId, ')
          ..write('poster: $poster, ')
          ..write('tag: $tag, ')
          ..write('note: $note, ')
          ..write('addedAt: $addedAt, ')
          ..write('extra: $extra, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SourcesTable extends Sources with TableInfo<$SourcesTable, Source> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _apiUrlMeta = const VerificationMeta('apiUrl');
  @override
  late final GeneratedColumn<String> apiUrl = GeneratedColumn<String>(
    'api_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _baseUrlMeta = const VerificationMeta(
    'baseUrl',
  );
  @override
  late final GeneratedColumn<String> baseUrl = GeneratedColumn<String>(
    'base_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<int> enabled = GeneratedColumn<int>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _healthMeta = const VerificationMeta('health');
  @override
  late final GeneratedColumn<String> health = GeneratedColumn<String>(
    'health',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown'),
  );
  static const VerificationMeta _lastCheckAtMeta = const VerificationMeta(
    'lastCheckAt',
  );
  @override
  late final GeneratedColumn<int> lastCheckAt = GeneratedColumn<int>(
    'last_check_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastLatencyMsMeta = const VerificationMeta(
    'lastLatencyMs',
  );
  @override
  late final GeneratedColumn<int> lastLatencyMs = GeneratedColumn<int>(
    'last_latency_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _configMeta = const VerificationMeta('config');
  @override
  late final GeneratedColumn<String> config = GeneratedColumn<String>(
    'config',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extMeta = const VerificationMeta('ext');
  @override
  late final GeneratedColumn<String> ext = GeneratedColumn<String>(
    'ext',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unreachableMeta = const VerificationMeta(
    'unreachable',
  );
  @override
  late final GeneratedColumn<int> unreachable = GeneratedColumn<int>(
    'unreachable',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    kind,
    apiUrl,
    baseUrl,
    username,
    enabled,
    priority,
    health,
    lastCheckAt,
    lastLatencyMs,
    config,
    ext,
    unreachable,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<Source> instance, {
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
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('api_url')) {
      context.handle(
        _apiUrlMeta,
        apiUrl.isAcceptableOrUnknown(data['api_url']!, _apiUrlMeta),
      );
    }
    if (data.containsKey('base_url')) {
      context.handle(
        _baseUrlMeta,
        baseUrl.isAcceptableOrUnknown(data['base_url']!, _baseUrlMeta),
      );
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('health')) {
      context.handle(
        _healthMeta,
        health.isAcceptableOrUnknown(data['health']!, _healthMeta),
      );
    }
    if (data.containsKey('last_check_at')) {
      context.handle(
        _lastCheckAtMeta,
        lastCheckAt.isAcceptableOrUnknown(
          data['last_check_at']!,
          _lastCheckAtMeta,
        ),
      );
    }
    if (data.containsKey('last_latency_ms')) {
      context.handle(
        _lastLatencyMsMeta,
        lastLatencyMs.isAcceptableOrUnknown(
          data['last_latency_ms']!,
          _lastLatencyMsMeta,
        ),
      );
    }
    if (data.containsKey('config')) {
      context.handle(
        _configMeta,
        config.isAcceptableOrUnknown(data['config']!, _configMeta),
      );
    }
    if (data.containsKey('ext')) {
      context.handle(
        _extMeta,
        ext.isAcceptableOrUnknown(data['ext']!, _extMeta),
      );
    }
    if (data.containsKey('unreachable')) {
      context.handle(
        _unreachableMeta,
        unreachable.isAcceptableOrUnknown(
          data['unreachable']!,
          _unreachableMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Source map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Source(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      apiUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}api_url'],
      ),
      baseUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_url'],
      ),
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}enabled'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      health: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}health'],
      )!,
      lastCheckAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_check_at'],
      ),
      lastLatencyMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_latency_ms'],
      ),
      config: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config'],
      ),
      ext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ext'],
      ),
      unreachable: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unreachable'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SourcesTable createAlias(String alias) {
    return $SourcesTable(attachedDatabase, alias);
  }
}

class Source extends DataClass implements Insertable<Source> {
  final String id;
  final String name;

  /// maccms/tvbox/emby/webdav/alist/direct
  final String kind;

  /// 采集站 api
  final String? apiUrl;

  /// 站点根
  final String? baseUrl;
  final String? username;
  final int enabled;

  /// 越大越优先
  final int priority;

  /// ok/slow/down/unknown
  final String health;
  final int? lastCheckAt;
  final int? lastLatencyMs;

  /// JSON：额外配置（headers/proxy 等）
  final String? config;

  /// TVBox 源的 ext 原文（type=3 的 csp_xxx 靠它初始化；其它源留空）
  final String? ext;

  /// 1 = 这个源被标记为「不可恢复解析失败」（地区限制/版权/大会员）
  /// 标记后不再自动打接口，用户手动点「仍要重试」才清（原 App 的 unreachable）
  final int unreachable;
  final int createdAt;
  const Source({
    required this.id,
    required this.name,
    required this.kind,
    this.apiUrl,
    this.baseUrl,
    this.username,
    required this.enabled,
    required this.priority,
    required this.health,
    this.lastCheckAt,
    this.lastLatencyMs,
    this.config,
    this.ext,
    required this.unreachable,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || apiUrl != null) {
      map['api_url'] = Variable<String>(apiUrl);
    }
    if (!nullToAbsent || baseUrl != null) {
      map['base_url'] = Variable<String>(baseUrl);
    }
    if (!nullToAbsent || username != null) {
      map['username'] = Variable<String>(username);
    }
    map['enabled'] = Variable<int>(enabled);
    map['priority'] = Variable<int>(priority);
    map['health'] = Variable<String>(health);
    if (!nullToAbsent || lastCheckAt != null) {
      map['last_check_at'] = Variable<int>(lastCheckAt);
    }
    if (!nullToAbsent || lastLatencyMs != null) {
      map['last_latency_ms'] = Variable<int>(lastLatencyMs);
    }
    if (!nullToAbsent || config != null) {
      map['config'] = Variable<String>(config);
    }
    if (!nullToAbsent || ext != null) {
      map['ext'] = Variable<String>(ext);
    }
    map['unreachable'] = Variable<int>(unreachable);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  SourcesCompanion toCompanion(bool nullToAbsent) {
    return SourcesCompanion(
      id: Value(id),
      name: Value(name),
      kind: Value(kind),
      apiUrl: apiUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(apiUrl),
      baseUrl: baseUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(baseUrl),
      username: username == null && nullToAbsent
          ? const Value.absent()
          : Value(username),
      enabled: Value(enabled),
      priority: Value(priority),
      health: Value(health),
      lastCheckAt: lastCheckAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCheckAt),
      lastLatencyMs: lastLatencyMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastLatencyMs),
      config: config == null && nullToAbsent
          ? const Value.absent()
          : Value(config),
      ext: ext == null && nullToAbsent ? const Value.absent() : Value(ext),
      unreachable: Value(unreachable),
      createdAt: Value(createdAt),
    );
  }

  factory Source.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Source(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      kind: serializer.fromJson<String>(json['kind']),
      apiUrl: serializer.fromJson<String?>(json['apiUrl']),
      baseUrl: serializer.fromJson<String?>(json['baseUrl']),
      username: serializer.fromJson<String?>(json['username']),
      enabled: serializer.fromJson<int>(json['enabled']),
      priority: serializer.fromJson<int>(json['priority']),
      health: serializer.fromJson<String>(json['health']),
      lastCheckAt: serializer.fromJson<int?>(json['lastCheckAt']),
      lastLatencyMs: serializer.fromJson<int?>(json['lastLatencyMs']),
      config: serializer.fromJson<String?>(json['config']),
      ext: serializer.fromJson<String?>(json['ext']),
      unreachable: serializer.fromJson<int>(json['unreachable']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String>(kind),
      'apiUrl': serializer.toJson<String?>(apiUrl),
      'baseUrl': serializer.toJson<String?>(baseUrl),
      'username': serializer.toJson<String?>(username),
      'enabled': serializer.toJson<int>(enabled),
      'priority': serializer.toJson<int>(priority),
      'health': serializer.toJson<String>(health),
      'lastCheckAt': serializer.toJson<int?>(lastCheckAt),
      'lastLatencyMs': serializer.toJson<int?>(lastLatencyMs),
      'config': serializer.toJson<String?>(config),
      'ext': serializer.toJson<String?>(ext),
      'unreachable': serializer.toJson<int>(unreachable),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  Source copyWith({
    String? id,
    String? name,
    String? kind,
    Value<String?> apiUrl = const Value.absent(),
    Value<String?> baseUrl = const Value.absent(),
    Value<String?> username = const Value.absent(),
    int? enabled,
    int? priority,
    String? health,
    Value<int?> lastCheckAt = const Value.absent(),
    Value<int?> lastLatencyMs = const Value.absent(),
    Value<String?> config = const Value.absent(),
    Value<String?> ext = const Value.absent(),
    int? unreachable,
    int? createdAt,
  }) => Source(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    apiUrl: apiUrl.present ? apiUrl.value : this.apiUrl,
    baseUrl: baseUrl.present ? baseUrl.value : this.baseUrl,
    username: username.present ? username.value : this.username,
    enabled: enabled ?? this.enabled,
    priority: priority ?? this.priority,
    health: health ?? this.health,
    lastCheckAt: lastCheckAt.present ? lastCheckAt.value : this.lastCheckAt,
    lastLatencyMs: lastLatencyMs.present
        ? lastLatencyMs.value
        : this.lastLatencyMs,
    config: config.present ? config.value : this.config,
    ext: ext.present ? ext.value : this.ext,
    unreachable: unreachable ?? this.unreachable,
    createdAt: createdAt ?? this.createdAt,
  );
  Source copyWithCompanion(SourcesCompanion data) {
    return Source(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      apiUrl: data.apiUrl.present ? data.apiUrl.value : this.apiUrl,
      baseUrl: data.baseUrl.present ? data.baseUrl.value : this.baseUrl,
      username: data.username.present ? data.username.value : this.username,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      priority: data.priority.present ? data.priority.value : this.priority,
      health: data.health.present ? data.health.value : this.health,
      lastCheckAt: data.lastCheckAt.present
          ? data.lastCheckAt.value
          : this.lastCheckAt,
      lastLatencyMs: data.lastLatencyMs.present
          ? data.lastLatencyMs.value
          : this.lastLatencyMs,
      config: data.config.present ? data.config.value : this.config,
      ext: data.ext.present ? data.ext.value : this.ext,
      unreachable: data.unreachable.present
          ? data.unreachable.value
          : this.unreachable,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Source(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('apiUrl: $apiUrl, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('username: $username, ')
          ..write('enabled: $enabled, ')
          ..write('priority: $priority, ')
          ..write('health: $health, ')
          ..write('lastCheckAt: $lastCheckAt, ')
          ..write('lastLatencyMs: $lastLatencyMs, ')
          ..write('config: $config, ')
          ..write('ext: $ext, ')
          ..write('unreachable: $unreachable, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    kind,
    apiUrl,
    baseUrl,
    username,
    enabled,
    priority,
    health,
    lastCheckAt,
    lastLatencyMs,
    config,
    ext,
    unreachable,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Source &&
          other.id == this.id &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.apiUrl == this.apiUrl &&
          other.baseUrl == this.baseUrl &&
          other.username == this.username &&
          other.enabled == this.enabled &&
          other.priority == this.priority &&
          other.health == this.health &&
          other.lastCheckAt == this.lastCheckAt &&
          other.lastLatencyMs == this.lastLatencyMs &&
          other.config == this.config &&
          other.ext == this.ext &&
          other.unreachable == this.unreachable &&
          other.createdAt == this.createdAt);
}

class SourcesCompanion extends UpdateCompanion<Source> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> kind;
  final Value<String?> apiUrl;
  final Value<String?> baseUrl;
  final Value<String?> username;
  final Value<int> enabled;
  final Value<int> priority;
  final Value<String> health;
  final Value<int?> lastCheckAt;
  final Value<int?> lastLatencyMs;
  final Value<String?> config;
  final Value<String?> ext;
  final Value<int> unreachable;
  final Value<int> createdAt;
  final Value<int> rowid;
  const SourcesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.apiUrl = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.username = const Value.absent(),
    this.enabled = const Value.absent(),
    this.priority = const Value.absent(),
    this.health = const Value.absent(),
    this.lastCheckAt = const Value.absent(),
    this.lastLatencyMs = const Value.absent(),
    this.config = const Value.absent(),
    this.ext = const Value.absent(),
    this.unreachable = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SourcesCompanion.insert({
    required String id,
    required String name,
    required String kind,
    this.apiUrl = const Value.absent(),
    this.baseUrl = const Value.absent(),
    this.username = const Value.absent(),
    this.enabled = const Value.absent(),
    this.priority = const Value.absent(),
    this.health = const Value.absent(),
    this.lastCheckAt = const Value.absent(),
    this.lastLatencyMs = const Value.absent(),
    this.config = const Value.absent(),
    this.ext = const Value.absent(),
    this.unreachable = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       kind = Value(kind),
       createdAt = Value(createdAt);
  static Insertable<Source> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<String>? apiUrl,
    Expression<String>? baseUrl,
    Expression<String>? username,
    Expression<int>? enabled,
    Expression<int>? priority,
    Expression<String>? health,
    Expression<int>? lastCheckAt,
    Expression<int>? lastLatencyMs,
    Expression<String>? config,
    Expression<String>? ext,
    Expression<int>? unreachable,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (apiUrl != null) 'api_url': apiUrl,
      if (baseUrl != null) 'base_url': baseUrl,
      if (username != null) 'username': username,
      if (enabled != null) 'enabled': enabled,
      if (priority != null) 'priority': priority,
      if (health != null) 'health': health,
      if (lastCheckAt != null) 'last_check_at': lastCheckAt,
      if (lastLatencyMs != null) 'last_latency_ms': lastLatencyMs,
      if (config != null) 'config': config,
      if (ext != null) 'ext': ext,
      if (unreachable != null) 'unreachable': unreachable,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SourcesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? kind,
    Value<String?>? apiUrl,
    Value<String?>? baseUrl,
    Value<String?>? username,
    Value<int>? enabled,
    Value<int>? priority,
    Value<String>? health,
    Value<int?>? lastCheckAt,
    Value<int?>? lastLatencyMs,
    Value<String?>? config,
    Value<String?>? ext,
    Value<int>? unreachable,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return SourcesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      apiUrl: apiUrl ?? this.apiUrl,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
      health: health ?? this.health,
      lastCheckAt: lastCheckAt ?? this.lastCheckAt,
      lastLatencyMs: lastLatencyMs ?? this.lastLatencyMs,
      config: config ?? this.config,
      ext: ext ?? this.ext,
      unreachable: unreachable ?? this.unreachable,
      createdAt: createdAt ?? this.createdAt,
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
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (apiUrl.present) {
      map['api_url'] = Variable<String>(apiUrl.value);
    }
    if (baseUrl.present) {
      map['base_url'] = Variable<String>(baseUrl.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<int>(enabled.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (health.present) {
      map['health'] = Variable<String>(health.value);
    }
    if (lastCheckAt.present) {
      map['last_check_at'] = Variable<int>(lastCheckAt.value);
    }
    if (lastLatencyMs.present) {
      map['last_latency_ms'] = Variable<int>(lastLatencyMs.value);
    }
    if (config.present) {
      map['config'] = Variable<String>(config.value);
    }
    if (ext.present) {
      map['ext'] = Variable<String>(ext.value);
    }
    if (unreachable.present) {
      map['unreachable'] = Variable<int>(unreachable.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SourcesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('apiUrl: $apiUrl, ')
          ..write('baseUrl: $baseUrl, ')
          ..write('username: $username, ')
          ..write('enabled: $enabled, ')
          ..write('priority: $priority, ')
          ..write('health: $health, ')
          ..write('lastCheckAt: $lastCheckAt, ')
          ..write('lastLatencyMs: $lastLatencyMs, ')
          ..write('config: $config, ')
          ..write('ext: $ext, ')
          ..write('unreachable: $unreachable, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AccountsTable extends Accounts with TableInfo<$AccountsTable, Account> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extraMeta = const VerificationMeta('extra');
  @override
  late final GeneratedColumn<String> extra = GeneratedColumn<String>(
    'extra',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown'),
  );
  static const VerificationMeta _lastVerifiedMeta = const VerificationMeta(
    'lastVerified',
  );
  @override
  late final GeneratedColumn<int> lastVerified = GeneratedColumn<int>(
    'last_verified',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    displayName,
    username,
    extra,
    status,
    lastVerified,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Account> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    if (data.containsKey('extra')) {
      context.handle(
        _extraMeta,
        extra.isAcceptableOrUnknown(data['extra']!, _extraMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('last_verified')) {
      context.handle(
        _lastVerifiedMeta,
        lastVerified.isAcceptableOrUnknown(
          data['last_verified']!,
          _lastVerifiedMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Account map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Account(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      ),
      extra: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extra'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      lastVerified: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_verified'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AccountsTable createAlias(String alias) {
    return $AccountsTable(attachedDatabase, alias);
  }
}

class Account extends DataClass implements Insertable<Account> {
  final String id;

  /// quark/pan115/pan123/tianyi/emby/webdav/alist
  final String kind;

  /// 用户备注名
  final String displayName;

  /// 账号（用于显示）
  final String? username;

  /// JSON：serverUrl/deviceId 等非敏感信息
  final String? extra;

  /// ok/expired/invalid/unknown
  final String status;
  final int? lastVerified;
  final int createdAt;
  const Account({
    required this.id,
    required this.kind,
    required this.displayName,
    this.username,
    this.extra,
    required this.status,
    this.lastVerified,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || username != null) {
      map['username'] = Variable<String>(username);
    }
    if (!nullToAbsent || extra != null) {
      map['extra'] = Variable<String>(extra);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || lastVerified != null) {
      map['last_verified'] = Variable<int>(lastVerified);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      id: Value(id),
      kind: Value(kind),
      displayName: Value(displayName),
      username: username == null && nullToAbsent
          ? const Value.absent()
          : Value(username),
      extra: extra == null && nullToAbsent
          ? const Value.absent()
          : Value(extra),
      status: Value(status),
      lastVerified: lastVerified == null && nullToAbsent
          ? const Value.absent()
          : Value(lastVerified),
      createdAt: Value(createdAt),
    );
  }

  factory Account.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Account(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      displayName: serializer.fromJson<String>(json['displayName']),
      username: serializer.fromJson<String?>(json['username']),
      extra: serializer.fromJson<String?>(json['extra']),
      status: serializer.fromJson<String>(json['status']),
      lastVerified: serializer.fromJson<int?>(json['lastVerified']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'displayName': serializer.toJson<String>(displayName),
      'username': serializer.toJson<String?>(username),
      'extra': serializer.toJson<String?>(extra),
      'status': serializer.toJson<String>(status),
      'lastVerified': serializer.toJson<int?>(lastVerified),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  Account copyWith({
    String? id,
    String? kind,
    String? displayName,
    Value<String?> username = const Value.absent(),
    Value<String?> extra = const Value.absent(),
    String? status,
    Value<int?> lastVerified = const Value.absent(),
    int? createdAt,
  }) => Account(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    displayName: displayName ?? this.displayName,
    username: username.present ? username.value : this.username,
    extra: extra.present ? extra.value : this.extra,
    status: status ?? this.status,
    lastVerified: lastVerified.present ? lastVerified.value : this.lastVerified,
    createdAt: createdAt ?? this.createdAt,
  );
  Account copyWithCompanion(AccountsCompanion data) {
    return Account(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      username: data.username.present ? data.username.value : this.username,
      extra: data.extra.present ? data.extra.value : this.extra,
      status: data.status.present ? data.status.value : this.status,
      lastVerified: data.lastVerified.present
          ? data.lastVerified.value
          : this.lastVerified,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Account(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('displayName: $displayName, ')
          ..write('username: $username, ')
          ..write('extra: $extra, ')
          ..write('status: $status, ')
          ..write('lastVerified: $lastVerified, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    displayName,
    username,
    extra,
    status,
    lastVerified,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Account &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.displayName == this.displayName &&
          other.username == this.username &&
          other.extra == this.extra &&
          other.status == this.status &&
          other.lastVerified == this.lastVerified &&
          other.createdAt == this.createdAt);
}

class AccountsCompanion extends UpdateCompanion<Account> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String> displayName;
  final Value<String?> username;
  final Value<String?> extra;
  final Value<String> status;
  final Value<int?> lastVerified;
  final Value<int> createdAt;
  final Value<int> rowid;
  const AccountsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.displayName = const Value.absent(),
    this.username = const Value.absent(),
    this.extra = const Value.absent(),
    this.status = const Value.absent(),
    this.lastVerified = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountsCompanion.insert({
    required String id,
    required String kind,
    required String displayName,
    this.username = const Value.absent(),
    this.extra = const Value.absent(),
    this.status = const Value.absent(),
    this.lastVerified = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       displayName = Value(displayName),
       createdAt = Value(createdAt);
  static Insertable<Account> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? displayName,
    Expression<String>? username,
    Expression<String>? extra,
    Expression<String>? status,
    Expression<int>? lastVerified,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (displayName != null) 'display_name': displayName,
      if (username != null) 'username': username,
      if (extra != null) 'extra': extra,
      if (status != null) 'status': status,
      if (lastVerified != null) 'last_verified': lastVerified,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountsCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<String>? displayName,
    Value<String?>? username,
    Value<String?>? extra,
    Value<String>? status,
    Value<int?>? lastVerified,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return AccountsCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      extra: extra ?? this.extra,
      status: status ?? this.status,
      lastVerified: lastVerified ?? this.lastVerified,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (extra.present) {
      map['extra'] = Variable<String>(extra.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (lastVerified.present) {
      map['last_verified'] = Variable<int>(lastVerified.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('displayName: $displayName, ')
          ..write('username: $username, ')
          ..write('extra: $extra, ')
          ..write('status: $status, ')
          ..write('lastVerified: $lastVerified, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DanmakuCacheTableTable extends DanmakuCacheTable
    with TableInfo<$DanmakuCacheTableTable, DanmakuRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DanmakuCacheTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
    'media_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _episodeIndexMeta = const VerificationMeta(
    'episodeIndex',
  );
  @override
  late final GeneratedColumn<int> episodeIndex = GeneratedColumn<int>(
    'episode_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countMeta = const VerificationMeta('count');
  @override
  late final GeneratedColumn<int> count = GeneratedColumn<int>(
    'count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
    'expires_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    mediaId,
    episodeIndex,
    payload,
    count,
    fetchedAt,
    expiresAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'danmaku_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<DanmakuRow> instance, {
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
    if (data.containsKey('episode_index')) {
      context.handle(
        _episodeIndexMeta,
        episodeIndex.isAcceptableOrUnknown(
          data['episode_index']!,
          _episodeIndexMeta,
        ),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('count')) {
      context.handle(
        _countMeta,
        count.isAcceptableOrUnknown(data['count']!, _countMeta),
      );
    } else if (isInserting) {
      context.missing(_countMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mediaId, episodeIndex};
  @override
  DanmakuRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DanmakuRow(
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_id'],
      )!,
      episodeIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode_index'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      count: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}count'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}expires_at'],
      )!,
    );
  }

  @override
  $DanmakuCacheTableTable createAlias(String alias) {
    return $DanmakuCacheTableTable(attachedDatabase, alias);
  }
}

class DanmakuRow extends DataClass implements Insertable<DanmakuRow> {
  /// 与 history.id 对应
  final String mediaId;
  final int episodeIndex;

  /// JSON 数组
  final String payload;
  final int count;
  final int fetchedAt;
  final int expiresAt;
  const DanmakuRow({
    required this.mediaId,
    required this.episodeIndex,
    required this.payload,
    required this.count,
    required this.fetchedAt,
    required this.expiresAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_id'] = Variable<String>(mediaId);
    map['episode_index'] = Variable<int>(episodeIndex);
    map['payload'] = Variable<String>(payload);
    map['count'] = Variable<int>(count);
    map['fetched_at'] = Variable<int>(fetchedAt);
    map['expires_at'] = Variable<int>(expiresAt);
    return map;
  }

  DanmakuCacheTableCompanion toCompanion(bool nullToAbsent) {
    return DanmakuCacheTableCompanion(
      mediaId: Value(mediaId),
      episodeIndex: Value(episodeIndex),
      payload: Value(payload),
      count: Value(count),
      fetchedAt: Value(fetchedAt),
      expiresAt: Value(expiresAt),
    );
  }

  factory DanmakuRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DanmakuRow(
      mediaId: serializer.fromJson<String>(json['mediaId']),
      episodeIndex: serializer.fromJson<int>(json['episodeIndex']),
      payload: serializer.fromJson<String>(json['payload']),
      count: serializer.fromJson<int>(json['count']),
      fetchedAt: serializer.fromJson<int>(json['fetchedAt']),
      expiresAt: serializer.fromJson<int>(json['expiresAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mediaId': serializer.toJson<String>(mediaId),
      'episodeIndex': serializer.toJson<int>(episodeIndex),
      'payload': serializer.toJson<String>(payload),
      'count': serializer.toJson<int>(count),
      'fetchedAt': serializer.toJson<int>(fetchedAt),
      'expiresAt': serializer.toJson<int>(expiresAt),
    };
  }

  DanmakuRow copyWith({
    String? mediaId,
    int? episodeIndex,
    String? payload,
    int? count,
    int? fetchedAt,
    int? expiresAt,
  }) => DanmakuRow(
    mediaId: mediaId ?? this.mediaId,
    episodeIndex: episodeIndex ?? this.episodeIndex,
    payload: payload ?? this.payload,
    count: count ?? this.count,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    expiresAt: expiresAt ?? this.expiresAt,
  );
  DanmakuRow copyWithCompanion(DanmakuCacheTableCompanion data) {
    return DanmakuRow(
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      episodeIndex: data.episodeIndex.present
          ? data.episodeIndex.value
          : this.episodeIndex,
      payload: data.payload.present ? data.payload.value : this.payload,
      count: data.count.present ? data.count.value : this.count,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DanmakuRow(')
          ..write('mediaId: $mediaId, ')
          ..write('episodeIndex: $episodeIndex, ')
          ..write('payload: $payload, ')
          ..write('count: $count, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('expiresAt: $expiresAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(mediaId, episodeIndex, payload, count, fetchedAt, expiresAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DanmakuRow &&
          other.mediaId == this.mediaId &&
          other.episodeIndex == this.episodeIndex &&
          other.payload == this.payload &&
          other.count == this.count &&
          other.fetchedAt == this.fetchedAt &&
          other.expiresAt == this.expiresAt);
}

class DanmakuCacheTableCompanion extends UpdateCompanion<DanmakuRow> {
  final Value<String> mediaId;
  final Value<int> episodeIndex;
  final Value<String> payload;
  final Value<int> count;
  final Value<int> fetchedAt;
  final Value<int> expiresAt;
  final Value<int> rowid;
  const DanmakuCacheTableCompanion({
    this.mediaId = const Value.absent(),
    this.episodeIndex = const Value.absent(),
    this.payload = const Value.absent(),
    this.count = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DanmakuCacheTableCompanion.insert({
    required String mediaId,
    this.episodeIndex = const Value.absent(),
    required String payload,
    required int count,
    required int fetchedAt,
    required int expiresAt,
    this.rowid = const Value.absent(),
  }) : mediaId = Value(mediaId),
       payload = Value(payload),
       count = Value(count),
       fetchedAt = Value(fetchedAt),
       expiresAt = Value(expiresAt);
  static Insertable<DanmakuRow> custom({
    Expression<String>? mediaId,
    Expression<int>? episodeIndex,
    Expression<String>? payload,
    Expression<int>? count,
    Expression<int>? fetchedAt,
    Expression<int>? expiresAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaId != null) 'media_id': mediaId,
      if (episodeIndex != null) 'episode_index': episodeIndex,
      if (payload != null) 'payload': payload,
      if (count != null) 'count': count,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DanmakuCacheTableCompanion copyWith({
    Value<String>? mediaId,
    Value<int>? episodeIndex,
    Value<String>? payload,
    Value<int>? count,
    Value<int>? fetchedAt,
    Value<int>? expiresAt,
    Value<int>? rowid,
  }) {
    return DanmakuCacheTableCompanion(
      mediaId: mediaId ?? this.mediaId,
      episodeIndex: episodeIndex ?? this.episodeIndex,
      payload: payload ?? this.payload,
      count: count ?? this.count,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (episodeIndex.present) {
      map['episode_index'] = Variable<int>(episodeIndex.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (count.present) {
      map['count'] = Variable<int>(count.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DanmakuCacheTableCompanion(')
          ..write('mediaId: $mediaId, ')
          ..write('episodeIndex: $episodeIndex, ')
          ..write('payload: $payload, ')
          ..write('count: $count, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SubtitlesTable extends Subtitles
    with TableInfo<$SubtitlesTable, SubtitleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SubtitlesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaUrlMeta = const VerificationMeta(
    'mediaUrl',
  );
  @override
  late final GeneratedColumn<String> mediaUrl = GeneratedColumn<String>(
    'media_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _langMeta = const VerificationMeta('lang');
  @override
  late final GeneratedColumn<String> lang = GeneratedColumn<String>(
    'lang',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('zh'),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('srt'),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastUsedAtMeta = const VerificationMeta(
    'lastUsedAt',
  );
  @override
  late final GeneratedColumn<int> lastUsedAt = GeneratedColumn<int>(
    'last_used_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    mediaUrl,
    lang,
    label,
    path,
    url,
    format,
    addedAt,
    lastUsedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'subtitles';
  @override
  VerificationContext validateIntegrity(
    Insertable<SubtitleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('media_url')) {
      context.handle(
        _mediaUrlMeta,
        mediaUrl.isAcceptableOrUnknown(data['media_url']!, _mediaUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaUrlMeta);
    }
    if (data.containsKey('lang')) {
      context.handle(
        _langMeta,
        lang.isAcceptableOrUnknown(data['lang']!, _langMeta),
      );
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
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
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SubtitleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SubtitleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      mediaUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_url'],
      )!,
      lang: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lang'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      ),
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      ),
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_used_at'],
      )!,
    );
  }

  @override
  $SubtitlesTable createAlias(String alias) {
    return $SubtitlesTable(attachedDatabase, alias);
  }
}

class SubtitleRow extends DataClass implements Insertable<SubtitleRow> {
  /// md5(mediaUrl + lang + (path ?? url)) 前 16 位
  final String id;

  /// 归属哪个片子（与 history.url 同一套）
  final String mediaUrl;
  final String lang;

  /// 显示名，如「简体中文」「ASS 特效」
  final String label;

  /// 本地绝对路径
  final String? path;

  /// 在线地址
  final String? url;
  final String format;
  final int addedAt;
  final int lastUsedAt;
  const SubtitleRow({
    required this.id,
    required this.mediaUrl,
    required this.lang,
    required this.label,
    this.path,
    this.url,
    required this.format,
    required this.addedAt,
    required this.lastUsedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['media_url'] = Variable<String>(mediaUrl);
    map['lang'] = Variable<String>(lang);
    map['label'] = Variable<String>(label);
    if (!nullToAbsent || path != null) {
      map['path'] = Variable<String>(path);
    }
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    map['format'] = Variable<String>(format);
    map['added_at'] = Variable<int>(addedAt);
    map['last_used_at'] = Variable<int>(lastUsedAt);
    return map;
  }

  SubtitlesCompanion toCompanion(bool nullToAbsent) {
    return SubtitlesCompanion(
      id: Value(id),
      mediaUrl: Value(mediaUrl),
      lang: Value(lang),
      label: Value(label),
      path: path == null && nullToAbsent ? const Value.absent() : Value(path),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
      format: Value(format),
      addedAt: Value(addedAt),
      lastUsedAt: Value(lastUsedAt),
    );
  }

  factory SubtitleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SubtitleRow(
      id: serializer.fromJson<String>(json['id']),
      mediaUrl: serializer.fromJson<String>(json['mediaUrl']),
      lang: serializer.fromJson<String>(json['lang']),
      label: serializer.fromJson<String>(json['label']),
      path: serializer.fromJson<String?>(json['path']),
      url: serializer.fromJson<String?>(json['url']),
      format: serializer.fromJson<String>(json['format']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
      lastUsedAt: serializer.fromJson<int>(json['lastUsedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'mediaUrl': serializer.toJson<String>(mediaUrl),
      'lang': serializer.toJson<String>(lang),
      'label': serializer.toJson<String>(label),
      'path': serializer.toJson<String?>(path),
      'url': serializer.toJson<String?>(url),
      'format': serializer.toJson<String>(format),
      'addedAt': serializer.toJson<int>(addedAt),
      'lastUsedAt': serializer.toJson<int>(lastUsedAt),
    };
  }

  SubtitleRow copyWith({
    String? id,
    String? mediaUrl,
    String? lang,
    String? label,
    Value<String?> path = const Value.absent(),
    Value<String?> url = const Value.absent(),
    String? format,
    int? addedAt,
    int? lastUsedAt,
  }) => SubtitleRow(
    id: id ?? this.id,
    mediaUrl: mediaUrl ?? this.mediaUrl,
    lang: lang ?? this.lang,
    label: label ?? this.label,
    path: path.present ? path.value : this.path,
    url: url.present ? url.value : this.url,
    format: format ?? this.format,
    addedAt: addedAt ?? this.addedAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );
  SubtitleRow copyWithCompanion(SubtitlesCompanion data) {
    return SubtitleRow(
      id: data.id.present ? data.id.value : this.id,
      mediaUrl: data.mediaUrl.present ? data.mediaUrl.value : this.mediaUrl,
      lang: data.lang.present ? data.lang.value : this.lang,
      label: data.label.present ? data.label.value : this.label,
      path: data.path.present ? data.path.value : this.path,
      url: data.url.present ? data.url.value : this.url,
      format: data.format.present ? data.format.value : this.format,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SubtitleRow(')
          ..write('id: $id, ')
          ..write('mediaUrl: $mediaUrl, ')
          ..write('lang: $lang, ')
          ..write('label: $label, ')
          ..write('path: $path, ')
          ..write('url: $url, ')
          ..write('format: $format, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastUsedAt: $lastUsedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    mediaUrl,
    lang,
    label,
    path,
    url,
    format,
    addedAt,
    lastUsedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SubtitleRow &&
          other.id == this.id &&
          other.mediaUrl == this.mediaUrl &&
          other.lang == this.lang &&
          other.label == this.label &&
          other.path == this.path &&
          other.url == this.url &&
          other.format == this.format &&
          other.addedAt == this.addedAt &&
          other.lastUsedAt == this.lastUsedAt);
}

class SubtitlesCompanion extends UpdateCompanion<SubtitleRow> {
  final Value<String> id;
  final Value<String> mediaUrl;
  final Value<String> lang;
  final Value<String> label;
  final Value<String?> path;
  final Value<String?> url;
  final Value<String> format;
  final Value<int> addedAt;
  final Value<int> lastUsedAt;
  final Value<int> rowid;
  const SubtitlesCompanion({
    this.id = const Value.absent(),
    this.mediaUrl = const Value.absent(),
    this.lang = const Value.absent(),
    this.label = const Value.absent(),
    this.path = const Value.absent(),
    this.url = const Value.absent(),
    this.format = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SubtitlesCompanion.insert({
    required String id,
    required String mediaUrl,
    this.lang = const Value.absent(),
    required String label,
    this.path = const Value.absent(),
    this.url = const Value.absent(),
    this.format = const Value.absent(),
    required int addedAt,
    this.lastUsedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       mediaUrl = Value(mediaUrl),
       label = Value(label),
       addedAt = Value(addedAt);
  static Insertable<SubtitleRow> custom({
    Expression<String>? id,
    Expression<String>? mediaUrl,
    Expression<String>? lang,
    Expression<String>? label,
    Expression<String>? path,
    Expression<String>? url,
    Expression<String>? format,
    Expression<int>? addedAt,
    Expression<int>? lastUsedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mediaUrl != null) 'media_url': mediaUrl,
      if (lang != null) 'lang': lang,
      if (label != null) 'label': label,
      if (path != null) 'path': path,
      if (url != null) 'url': url,
      if (format != null) 'format': format,
      if (addedAt != null) 'added_at': addedAt,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SubtitlesCompanion copyWith({
    Value<String>? id,
    Value<String>? mediaUrl,
    Value<String>? lang,
    Value<String>? label,
    Value<String?>? path,
    Value<String?>? url,
    Value<String>? format,
    Value<int>? addedAt,
    Value<int>? lastUsedAt,
    Value<int>? rowid,
  }) {
    return SubtitlesCompanion(
      id: id ?? this.id,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      lang: lang ?? this.lang,
      label: label ?? this.label,
      path: path ?? this.path,
      url: url ?? this.url,
      format: format ?? this.format,
      addedAt: addedAt ?? this.addedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (mediaUrl.present) {
      map['media_url'] = Variable<String>(mediaUrl.value);
    }
    if (lang.present) {
      map['lang'] = Variable<String>(lang.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<int>(lastUsedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SubtitlesCompanion(')
          ..write('id: $id, ')
          ..write('mediaUrl: $mediaUrl, ')
          ..write('lang: $lang, ')
          ..write('label: $label, ')
          ..write('path: $path, ')
          ..write('url: $url, ')
          ..write('format: $format, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, TagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaUrlMeta = const VerificationMeta(
    'mediaUrl',
  );
  @override
  late final GeneratedColumn<String> mediaUrl = GeneratedColumn<String>(
    'media_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0xFF4884EE),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, mediaUrl, name, color, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<TagRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('media_url')) {
      context.handle(
        _mediaUrlMeta,
        mediaUrl.isAcceptableOrUnknown(data['media_url']!, _mediaUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaUrlMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TagRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      mediaUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_url'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class TagRow extends DataClass implements Insertable<TagRow> {
  /// md5(mediaUrl + name) 前 16 位
  final String id;

  /// 归属哪个片子（与 history.url 同一套）
  final String mediaUrl;

  /// 标签文本，如「周更」「收藏夹」
  final String name;

  /// 颜色（ARGB），默认主题蓝
  final int color;
  final int addedAt;
  const TagRow({
    required this.id,
    required this.mediaUrl,
    required this.name,
    required this.color,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['media_url'] = Variable<String>(mediaUrl);
    map['name'] = Variable<String>(name);
    map['color'] = Variable<int>(color);
    map['added_at'] = Variable<int>(addedAt);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      mediaUrl: Value(mediaUrl),
      name: Value(name),
      color: Value(color),
      addedAt: Value(addedAt),
    );
  }

  factory TagRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TagRow(
      id: serializer.fromJson<String>(json['id']),
      mediaUrl: serializer.fromJson<String>(json['mediaUrl']),
      name: serializer.fromJson<String>(json['name']),
      color: serializer.fromJson<int>(json['color']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'mediaUrl': serializer.toJson<String>(mediaUrl),
      'name': serializer.toJson<String>(name),
      'color': serializer.toJson<int>(color),
      'addedAt': serializer.toJson<int>(addedAt),
    };
  }

  TagRow copyWith({
    String? id,
    String? mediaUrl,
    String? name,
    int? color,
    int? addedAt,
  }) => TagRow(
    id: id ?? this.id,
    mediaUrl: mediaUrl ?? this.mediaUrl,
    name: name ?? this.name,
    color: color ?? this.color,
    addedAt: addedAt ?? this.addedAt,
  );
  TagRow copyWithCompanion(TagsCompanion data) {
    return TagRow(
      id: data.id.present ? data.id.value : this.id,
      mediaUrl: data.mediaUrl.present ? data.mediaUrl.value : this.mediaUrl,
      name: data.name.present ? data.name.value : this.name,
      color: data.color.present ? data.color.value : this.color,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TagRow(')
          ..write('id: $id, ')
          ..write('mediaUrl: $mediaUrl, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, mediaUrl, name, color, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TagRow &&
          other.id == this.id &&
          other.mediaUrl == this.mediaUrl &&
          other.name == this.name &&
          other.color == this.color &&
          other.addedAt == this.addedAt);
}

class TagsCompanion extends UpdateCompanion<TagRow> {
  final Value<String> id;
  final Value<String> mediaUrl;
  final Value<String> name;
  final Value<int> color;
  final Value<int> addedAt;
  final Value<int> rowid;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.mediaUrl = const Value.absent(),
    this.name = const Value.absent(),
    this.color = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagsCompanion.insert({
    required String id,
    required String mediaUrl,
    required String name,
    this.color = const Value.absent(),
    required int addedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       mediaUrl = Value(mediaUrl),
       name = Value(name),
       addedAt = Value(addedAt);
  static Insertable<TagRow> custom({
    Expression<String>? id,
    Expression<String>? mediaUrl,
    Expression<String>? name,
    Expression<int>? color,
    Expression<int>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mediaUrl != null) 'media_url': mediaUrl,
      if (name != null) 'name': name,
      if (color != null) 'color': color,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagsCompanion copyWith({
    Value<String>? id,
    Value<String>? mediaUrl,
    Value<String>? name,
    Value<int>? color,
    Value<int>? addedAt,
    Value<int>? rowid,
  }) {
    return TagsCompanion(
      id: id ?? this.id,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      name: name ?? this.name,
      color: color ?? this.color,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (mediaUrl.present) {
      map['media_url'] = Variable<String>(mediaUrl.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('mediaUrl: $mediaUrl, ')
          ..write('name: $name, ')
          ..write('color: $color, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SourceRatingsTable extends SourceRatings
    with TableInfo<$SourceRatingsTable, SourceRating> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SourceRatingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<int> score = GeneratedColumn<int>(
    'score',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ratedAtMeta = const VerificationMeta(
    'ratedAt',
  );
  @override
  late final GeneratedColumn<int> ratedAt = GeneratedColumn<int>(
    'rated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [sourceId, score, ratedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'source_ratings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SourceRating> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    } else if (isInserting) {
      context.missing(_scoreMeta);
    }
    if (data.containsKey('rated_at')) {
      context.handle(
        _ratedAtMeta,
        ratedAt.isAcceptableOrUnknown(data['rated_at']!, _ratedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_ratedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId};
  @override
  SourceRating map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SourceRating(
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}score'],
      )!,
      ratedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rated_at'],
      )!,
    );
  }

  @override
  $SourceRatingsTable createAlias(String alias) {
    return $SourceRatingsTable(attachedDatabase, alias);
  }
}

class SourceRating extends DataClass implements Insertable<SourceRating> {
  /// 与 sources.id 对应
  final String sourceId;

  /// 1..5
  final int score;
  final int ratedAt;
  const SourceRating({
    required this.sourceId,
    required this.score,
    required this.ratedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<String>(sourceId);
    map['score'] = Variable<int>(score);
    map['rated_at'] = Variable<int>(ratedAt);
    return map;
  }

  SourceRatingsCompanion toCompanion(bool nullToAbsent) {
    return SourceRatingsCompanion(
      sourceId: Value(sourceId),
      score: Value(score),
      ratedAt: Value(ratedAt),
    );
  }

  factory SourceRating.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SourceRating(
      sourceId: serializer.fromJson<String>(json['sourceId']),
      score: serializer.fromJson<int>(json['score']),
      ratedAt: serializer.fromJson<int>(json['ratedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<String>(sourceId),
      'score': serializer.toJson<int>(score),
      'ratedAt': serializer.toJson<int>(ratedAt),
    };
  }

  SourceRating copyWith({String? sourceId, int? score, int? ratedAt}) =>
      SourceRating(
        sourceId: sourceId ?? this.sourceId,
        score: score ?? this.score,
        ratedAt: ratedAt ?? this.ratedAt,
      );
  SourceRating copyWithCompanion(SourceRatingsCompanion data) {
    return SourceRating(
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      score: data.score.present ? data.score.value : this.score,
      ratedAt: data.ratedAt.present ? data.ratedAt.value : this.ratedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SourceRating(')
          ..write('sourceId: $sourceId, ')
          ..write('score: $score, ')
          ..write('ratedAt: $ratedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sourceId, score, ratedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceRating &&
          other.sourceId == this.sourceId &&
          other.score == this.score &&
          other.ratedAt == this.ratedAt);
}

class SourceRatingsCompanion extends UpdateCompanion<SourceRating> {
  final Value<String> sourceId;
  final Value<int> score;
  final Value<int> ratedAt;
  final Value<int> rowid;
  const SourceRatingsCompanion({
    this.sourceId = const Value.absent(),
    this.score = const Value.absent(),
    this.ratedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SourceRatingsCompanion.insert({
    required String sourceId,
    required int score,
    required int ratedAt,
    this.rowid = const Value.absent(),
  }) : sourceId = Value(sourceId),
       score = Value(score),
       ratedAt = Value(ratedAt);
  static Insertable<SourceRating> custom({
    Expression<String>? sourceId,
    Expression<int>? score,
    Expression<int>? ratedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (score != null) 'score': score,
      if (ratedAt != null) 'rated_at': ratedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SourceRatingsCompanion copyWith({
    Value<String>? sourceId,
    Value<int>? score,
    Value<int>? ratedAt,
    Value<int>? rowid,
  }) {
    return SourceRatingsCompanion(
      sourceId: sourceId ?? this.sourceId,
      score: score ?? this.score,
      ratedAt: ratedAt ?? this.ratedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (score.present) {
      map['score'] = Variable<int>(score.value);
    }
    if (ratedAt.present) {
      map['rated_at'] = Variable<int>(ratedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SourceRatingsCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('score: $score, ')
          ..write('ratedAt: $ratedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PlaylistsTable extends Playlists
    with TableInfo<$PlaylistsTable, Playlist> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaUrlMeta = const VerificationMeta(
    'mediaUrl',
  );
  @override
  late final GeneratedColumn<String> mediaUrl = GeneratedColumn<String>(
    'media_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaTitleMeta = const VerificationMeta(
    'mediaTitle',
  );
  @override
  late final GeneratedColumn<String> mediaTitle = GeneratedColumn<String>(
    'media_title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortIndexMeta = const VerificationMeta(
    'sortIndex',
  );
  @override
  late final GeneratedColumn<int> sortIndex = GeneratedColumn<int>(
    'sort_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    mediaUrl,
    mediaTitle,
    sortIndex,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlists';
  @override
  VerificationContext validateIntegrity(
    Insertable<Playlist> instance, {
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
    if (data.containsKey('media_url')) {
      context.handle(
        _mediaUrlMeta,
        mediaUrl.isAcceptableOrUnknown(data['media_url']!, _mediaUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaUrlMeta);
    }
    if (data.containsKey('media_title')) {
      context.handle(
        _mediaTitleMeta,
        mediaTitle.isAcceptableOrUnknown(data['media_title']!, _mediaTitleMeta),
      );
    }
    if (data.containsKey('sort_index')) {
      context.handle(
        _sortIndexMeta,
        sortIndex.isAcceptableOrUnknown(data['sort_index']!, _sortIndexMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Playlist map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Playlist(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      mediaUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_url'],
      )!,
      mediaTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_title'],
      ),
      sortIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_index'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $PlaylistsTable createAlias(String alias) {
    return $PlaylistsTable(attachedDatabase, alias);
  }
}

class Playlist extends DataClass implements Insertable<Playlist> {
  /// md5(name + '|' + addedAt + '|' + mediaUrl) 前 16 位
  final String id;

  /// 列表名（同名不允许）
  final String name;

  /// 条目指向的片子（与 history.url 同一套）
  final String mediaUrl;

  /// 条目显示名（片名/集名）
  final String? mediaTitle;

  /// 列表内顺序，越小越靠前
  final int sortIndex;
  final int addedAt;
  const Playlist({
    required this.id,
    required this.name,
    required this.mediaUrl,
    this.mediaTitle,
    required this.sortIndex,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['media_url'] = Variable<String>(mediaUrl);
    if (!nullToAbsent || mediaTitle != null) {
      map['media_title'] = Variable<String>(mediaTitle);
    }
    map['sort_index'] = Variable<int>(sortIndex);
    map['added_at'] = Variable<int>(addedAt);
    return map;
  }

  PlaylistsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistsCompanion(
      id: Value(id),
      name: Value(name),
      mediaUrl: Value(mediaUrl),
      mediaTitle: mediaTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaTitle),
      sortIndex: Value(sortIndex),
      addedAt: Value(addedAt),
    );
  }

  factory Playlist.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Playlist(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      mediaUrl: serializer.fromJson<String>(json['mediaUrl']),
      mediaTitle: serializer.fromJson<String?>(json['mediaTitle']),
      sortIndex: serializer.fromJson<int>(json['sortIndex']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'mediaUrl': serializer.toJson<String>(mediaUrl),
      'mediaTitle': serializer.toJson<String?>(mediaTitle),
      'sortIndex': serializer.toJson<int>(sortIndex),
      'addedAt': serializer.toJson<int>(addedAt),
    };
  }

  Playlist copyWith({
    String? id,
    String? name,
    String? mediaUrl,
    Value<String?> mediaTitle = const Value.absent(),
    int? sortIndex,
    int? addedAt,
  }) => Playlist(
    id: id ?? this.id,
    name: name ?? this.name,
    mediaUrl: mediaUrl ?? this.mediaUrl,
    mediaTitle: mediaTitle.present ? mediaTitle.value : this.mediaTitle,
    sortIndex: sortIndex ?? this.sortIndex,
    addedAt: addedAt ?? this.addedAt,
  );
  Playlist copyWithCompanion(PlaylistsCompanion data) {
    return Playlist(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      mediaUrl: data.mediaUrl.present ? data.mediaUrl.value : this.mediaUrl,
      mediaTitle: data.mediaTitle.present
          ? data.mediaTitle.value
          : this.mediaTitle,
      sortIndex: data.sortIndex.present ? data.sortIndex.value : this.sortIndex,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Playlist(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('mediaUrl: $mediaUrl, ')
          ..write('mediaTitle: $mediaTitle, ')
          ..write('sortIndex: $sortIndex, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, mediaUrl, mediaTitle, sortIndex, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Playlist &&
          other.id == this.id &&
          other.name == this.name &&
          other.mediaUrl == this.mediaUrl &&
          other.mediaTitle == this.mediaTitle &&
          other.sortIndex == this.sortIndex &&
          other.addedAt == this.addedAt);
}

class PlaylistsCompanion extends UpdateCompanion<Playlist> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> mediaUrl;
  final Value<String?> mediaTitle;
  final Value<int> sortIndex;
  final Value<int> addedAt;
  final Value<int> rowid;
  const PlaylistsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.mediaUrl = const Value.absent(),
    this.mediaTitle = const Value.absent(),
    this.sortIndex = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlaylistsCompanion.insert({
    required String id,
    required String name,
    required String mediaUrl,
    this.mediaTitle = const Value.absent(),
    this.sortIndex = const Value.absent(),
    required int addedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       mediaUrl = Value(mediaUrl),
       addedAt = Value(addedAt);
  static Insertable<Playlist> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? mediaUrl,
    Expression<String>? mediaTitle,
    Expression<int>? sortIndex,
    Expression<int>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (mediaUrl != null) 'media_url': mediaUrl,
      if (mediaTitle != null) 'media_title': mediaTitle,
      if (sortIndex != null) 'sort_index': sortIndex,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlaylistsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? mediaUrl,
    Value<String?>? mediaTitle,
    Value<int>? sortIndex,
    Value<int>? addedAt,
    Value<int>? rowid,
  }) {
    return PlaylistsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaTitle: mediaTitle ?? this.mediaTitle,
      sortIndex: sortIndex ?? this.sortIndex,
      addedAt: addedAt ?? this.addedAt,
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
    if (mediaUrl.present) {
      map['media_url'] = Variable<String>(mediaUrl.value);
    }
    if (mediaTitle.present) {
      map['media_title'] = Variable<String>(mediaTitle.value);
    }
    if (sortIndex.present) {
      map['sort_index'] = Variable<int>(sortIndex.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('mediaUrl: $mediaUrl, ')
          ..write('mediaTitle: $mediaTitle, ')
          ..write('sortIndex: $sortIndex, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChapterMarksTable extends ChapterMarks
    with TableInfo<$ChapterMarksTable, ChapterMark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChapterMarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
    'media_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _introEndMeta = const VerificationMeta(
    'introEnd',
  );
  @override
  late final GeneratedColumn<double> introEnd = GeneratedColumn<double>(
    'intro_end',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(-1),
  );
  static const VerificationMeta _outroStartMeta = const VerificationMeta(
    'outroStart',
  );
  @override
  late final GeneratedColumn<double> outroStart = GeneratedColumn<double>(
    'outro_start',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(-1),
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    mediaId,
    introEnd,
    outroStart,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chapter_marks';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChapterMark> instance, {
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
    if (data.containsKey('intro_end')) {
      context.handle(
        _introEndMeta,
        introEnd.isAcceptableOrUnknown(data['intro_end']!, _introEndMeta),
      );
    }
    if (data.containsKey('outro_start')) {
      context.handle(
        _outroStartMeta,
        outroStart.isAcceptableOrUnknown(data['outro_start']!, _outroStartMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mediaId};
  @override
  ChapterMark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChapterMark(
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_id'],
      )!,
      introEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}intro_end'],
      )!,
      outroStart: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}outro_start'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ChapterMarksTable createAlias(String alias) {
    return $ChapterMarksTable(attachedDatabase, alias);
  }
}

class ChapterMark extends DataClass implements Insertable<ChapterMark> {
  /// 复用 LibraryMedia.id 规则：md5(url) 前 16 位（同片换源不复用）
  final String mediaId;

  /// 片头结束（秒）；-1 = 未设
  final double introEnd;

  /// 片尾开始（秒）；-1 = 未设
  final double outroStart;
  final DateTime updatedAt;
  const ChapterMark({
    required this.mediaId,
    required this.introEnd,
    required this.outroStart,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_id'] = Variable<String>(mediaId);
    map['intro_end'] = Variable<double>(introEnd);
    map['outro_start'] = Variable<double>(outroStart);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ChapterMarksCompanion toCompanion(bool nullToAbsent) {
    return ChapterMarksCompanion(
      mediaId: Value(mediaId),
      introEnd: Value(introEnd),
      outroStart: Value(outroStart),
      updatedAt: Value(updatedAt),
    );
  }

  factory ChapterMark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChapterMark(
      mediaId: serializer.fromJson<String>(json['mediaId']),
      introEnd: serializer.fromJson<double>(json['introEnd']),
      outroStart: serializer.fromJson<double>(json['outroStart']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mediaId': serializer.toJson<String>(mediaId),
      'introEnd': serializer.toJson<double>(introEnd),
      'outroStart': serializer.toJson<double>(outroStart),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ChapterMark copyWith({
    String? mediaId,
    double? introEnd,
    double? outroStart,
    DateTime? updatedAt,
  }) => ChapterMark(
    mediaId: mediaId ?? this.mediaId,
    introEnd: introEnd ?? this.introEnd,
    outroStart: outroStart ?? this.outroStart,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ChapterMark copyWithCompanion(ChapterMarksCompanion data) {
    return ChapterMark(
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      introEnd: data.introEnd.present ? data.introEnd.value : this.introEnd,
      outroStart: data.outroStart.present
          ? data.outroStart.value
          : this.outroStart,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChapterMark(')
          ..write('mediaId: $mediaId, ')
          ..write('introEnd: $introEnd, ')
          ..write('outroStart: $outroStart, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mediaId, introEnd, outroStart, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChapterMark &&
          other.mediaId == this.mediaId &&
          other.introEnd == this.introEnd &&
          other.outroStart == this.outroStart &&
          other.updatedAt == this.updatedAt);
}

class ChapterMarksCompanion extends UpdateCompanion<ChapterMark> {
  final Value<String> mediaId;
  final Value<double> introEnd;
  final Value<double> outroStart;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ChapterMarksCompanion({
    this.mediaId = const Value.absent(),
    this.introEnd = const Value.absent(),
    this.outroStart = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChapterMarksCompanion.insert({
    required String mediaId,
    this.introEnd = const Value.absent(),
    this.outroStart = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : mediaId = Value(mediaId),
       updatedAt = Value(updatedAt);
  static Insertable<ChapterMark> custom({
    Expression<String>? mediaId,
    Expression<double>? introEnd,
    Expression<double>? outroStart,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaId != null) 'media_id': mediaId,
      if (introEnd != null) 'intro_end': introEnd,
      if (outroStart != null) 'outro_start': outroStart,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChapterMarksCompanion copyWith({
    Value<String>? mediaId,
    Value<double>? introEnd,
    Value<double>? outroStart,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ChapterMarksCompanion(
      mediaId: mediaId ?? this.mediaId,
      introEnd: introEnd ?? this.introEnd,
      outroStart: outroStart ?? this.outroStart,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (introEnd.present) {
      map['intro_end'] = Variable<double>(introEnd.value);
    }
    if (outroStart.present) {
      map['outro_start'] = Variable<double>(outroStart.value);
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
    return (StringBuffer('ChapterMarksCompanion(')
          ..write('mediaId: $mediaId, ')
          ..write('introEnd: $introEnd, ')
          ..write('outroStart: $outroStart, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $RoomsTable rooms = $RoomsTable(this);
  late final $HistoryTableTable historyTable = $HistoryTableTable(this);
  late final $FavoritesTable favorites = $FavoritesTable(this);
  late final $SourcesTable sources = $SourcesTable(this);
  late final $AccountsTable accounts = $AccountsTable(this);
  late final $DanmakuCacheTableTable danmakuCacheTable =
      $DanmakuCacheTableTable(this);
  late final $SubtitlesTable subtitles = $SubtitlesTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $SourceRatingsTable sourceRatings = $SourceRatingsTable(this);
  late final $PlaylistsTable playlists = $PlaylistsTable(this);
  late final $ChapterMarksTable chapterMarks = $ChapterMarksTable(this);
  late final Index idxRoomsLastJoined = Index(
    'idx_rooms_last_joined',
    'CREATE INDEX idx_rooms_last_joined ON rooms (last_joined_at)',
  );
  late final Index idxRoomsMode = Index(
    'idx_rooms_mode',
    'CREATE INDEX idx_rooms_mode ON rooms (mode)',
  );
  late final Index idxHistoryWatched = Index(
    'idx_history_watched',
    'CREATE INDEX idx_history_watched ON history (watched_at)',
  );
  late final Index idxHistorySeries = Index(
    'idx_history_series',
    'CREATE INDEX idx_history_series ON history (series_id)',
  );
  late final Index idxHistoryUrl = Index(
    'idx_history_url',
    'CREATE UNIQUE INDEX idx_history_url ON history (url)',
  );
  late final Index idxFavUrl = Index(
    'idx_fav_url',
    'CREATE UNIQUE INDEX idx_fav_url ON favorites (url)',
  );
  late final Index idxFavTag = Index(
    'idx_fav_tag',
    'CREATE INDEX idx_fav_tag ON favorites (tag)',
  );
  late final Index idxSourcesKind = Index(
    'idx_sources_kind',
    'CREATE INDEX idx_sources_kind ON sources (kind)',
  );
  late final Index idxSourcesPriority = Index(
    'idx_sources_priority',
    'CREATE INDEX idx_sources_priority ON sources (priority)',
  );
  late final Index idxAccountsKind = Index(
    'idx_accounts_kind',
    'CREATE INDEX idx_accounts_kind ON accounts (kind)',
  );
  late final Index idxDanmakuExpires = Index(
    'idx_danmaku_expires',
    'CREATE INDEX idx_danmaku_expires ON danmaku_cache (expires_at)',
  );
  late final Index idxTagsMedia = Index(
    'idx_tags_media',
    'CREATE INDEX idx_tags_media ON tags (media_url)',
  );
  late final Index idxTagsName = Index(
    'idx_tags_name',
    'CREATE INDEX idx_tags_name ON tags (name)',
  );
  late final RoomDao roomDao = RoomDao(this as AppDatabase);
  late final HistoryDao historyDao = HistoryDao(this as AppDatabase);
  late final FavoriteDao favoriteDao = FavoriteDao(this as AppDatabase);
  late final SourceDao sourceDao = SourceDao(this as AppDatabase);
  late final AccountDao accountDao = AccountDao(this as AppDatabase);
  late final DanmakuDao danmakuDao = DanmakuDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    rooms,
    historyTable,
    favorites,
    sources,
    accounts,
    danmakuCacheTable,
    subtitles,
    tags,
    sourceRatings,
    playlists,
    chapterMarks,
    idxRoomsLastJoined,
    idxRoomsMode,
    idxHistoryWatched,
    idxHistorySeries,
    idxHistoryUrl,
    idxFavUrl,
    idxFavTag,
    idxSourcesKind,
    idxSourcesPriority,
    idxAccountsKind,
    idxDanmakuExpires,
    idxTagsMedia,
    idxTagsName,
  ];
}

typedef $$RoomsTableCreateCompanionBuilder =
    RoomsCompanion Function({
      required String id,
      required String name,
      required String code,
      required String mode,
      Value<String?> joinUrl,
      Value<String?> hostName,
      Value<String?> passwordHash,
      Value<int> isFavorite,
      Value<int> memberCount,
      required int lastJoinedAt,
      required int createdAt,
      Value<String?> extra,
      Value<int> rowid,
    });
typedef $$RoomsTableUpdateCompanionBuilder =
    RoomsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> code,
      Value<String> mode,
      Value<String?> joinUrl,
      Value<String?> hostName,
      Value<String?> passwordHash,
      Value<int> isFavorite,
      Value<int> memberCount,
      Value<int> lastJoinedAt,
      Value<int> createdAt,
      Value<String?> extra,
      Value<int> rowid,
    });

class $$RoomsTableFilterComposer extends Composer<_$AppDatabase, $RoomsTable> {
  $$RoomsTableFilterComposer({
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

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get joinUrl => $composableBuilder(
    column: $table.joinUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostName => $composableBuilder(
    column: $table.hostName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get passwordHash => $composableBuilder(
    column: $table.passwordHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get memberCount => $composableBuilder(
    column: $table.memberCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastJoinedAt => $composableBuilder(
    column: $table.lastJoinedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RoomsTableOrderingComposer
    extends Composer<_$AppDatabase, $RoomsTable> {
  $$RoomsTableOrderingComposer({
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

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get joinUrl => $composableBuilder(
    column: $table.joinUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostName => $composableBuilder(
    column: $table.hostName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get passwordHash => $composableBuilder(
    column: $table.passwordHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get memberCount => $composableBuilder(
    column: $table.memberCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastJoinedAt => $composableBuilder(
    column: $table.lastJoinedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RoomsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RoomsTable> {
  $$RoomsTableAnnotationComposer({
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

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get joinUrl =>
      $composableBuilder(column: $table.joinUrl, builder: (column) => column);

  GeneratedColumn<String> get hostName =>
      $composableBuilder(column: $table.hostName, builder: (column) => column);

  GeneratedColumn<String> get passwordHash => $composableBuilder(
    column: $table.passwordHash,
    builder: (column) => column,
  );

  GeneratedColumn<int> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<int> get memberCount => $composableBuilder(
    column: $table.memberCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastJoinedAt => $composableBuilder(
    column: $table.lastJoinedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get extra =>
      $composableBuilder(column: $table.extra, builder: (column) => column);
}

class $$RoomsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RoomsTable,
          Room,
          $$RoomsTableFilterComposer,
          $$RoomsTableOrderingComposer,
          $$RoomsTableAnnotationComposer,
          $$RoomsTableCreateCompanionBuilder,
          $$RoomsTableUpdateCompanionBuilder,
          (Room, BaseReferences<_$AppDatabase, $RoomsTable, Room>),
          Room,
          PrefetchHooks Function()
        > {
  $$RoomsTableTableManager(_$AppDatabase db, $RoomsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoomsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoomsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoomsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String?> joinUrl = const Value.absent(),
                Value<String?> hostName = const Value.absent(),
                Value<String?> passwordHash = const Value.absent(),
                Value<int> isFavorite = const Value.absent(),
                Value<int> memberCount = const Value.absent(),
                Value<int> lastJoinedAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String?> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoomsCompanion(
                id: id,
                name: name,
                code: code,
                mode: mode,
                joinUrl: joinUrl,
                hostName: hostName,
                passwordHash: passwordHash,
                isFavorite: isFavorite,
                memberCount: memberCount,
                lastJoinedAt: lastJoinedAt,
                createdAt: createdAt,
                extra: extra,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String code,
                required String mode,
                Value<String?> joinUrl = const Value.absent(),
                Value<String?> hostName = const Value.absent(),
                Value<String?> passwordHash = const Value.absent(),
                Value<int> isFavorite = const Value.absent(),
                Value<int> memberCount = const Value.absent(),
                required int lastJoinedAt,
                required int createdAt,
                Value<String?> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoomsCompanion.insert(
                id: id,
                name: name,
                code: code,
                mode: mode,
                joinUrl: joinUrl,
                hostName: hostName,
                passwordHash: passwordHash,
                isFavorite: isFavorite,
                memberCount: memberCount,
                lastJoinedAt: lastJoinedAt,
                createdAt: createdAt,
                extra: extra,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RoomsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RoomsTable,
      Room,
      $$RoomsTableFilterComposer,
      $$RoomsTableOrderingComposer,
      $$RoomsTableAnnotationComposer,
      $$RoomsTableCreateCompanionBuilder,
      $$RoomsTableUpdateCompanionBuilder,
      (Room, BaseReferences<_$AppDatabase, $RoomsTable, Room>),
      Room,
      PrefetchHooks Function()
    >;
typedef $$HistoryTableTableCreateCompanionBuilder =
    HistoryTableCompanion Function({
      required String id,
      required String title,
      required String url,
      required String sourceKind,
      Value<String?> sourceId,
      Value<String?> poster,
      Value<double> position,
      Value<double> duration,
      Value<int> watchedSeconds,
      Value<int?> episodeIndex,
      Value<String?> seriesId,
      required int watchedAt,
      required int createdAt,
      Value<String?> extra,
      Value<int> rowid,
    });
typedef $$HistoryTableTableUpdateCompanionBuilder =
    HistoryTableCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> url,
      Value<String> sourceKind,
      Value<String?> sourceId,
      Value<String?> poster,
      Value<double> position,
      Value<double> duration,
      Value<int> watchedSeconds,
      Value<int?> episodeIndex,
      Value<String?> seriesId,
      Value<int> watchedAt,
      Value<int> createdAt,
      Value<String?> extra,
      Value<int> rowid,
    });

class $$HistoryTableTableFilterComposer
    extends Composer<_$AppDatabase, $HistoryTableTable> {
  $$HistoryTableTableFilterComposer({
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

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get poster => $composableBuilder(
    column: $table.poster,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get watchedSeconds => $composableBuilder(
    column: $table.watchedSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episodeIndex => $composableBuilder(
    column: $table.episodeIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get watchedAt => $composableBuilder(
    column: $table.watchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HistoryTableTableOrderingComposer
    extends Composer<_$AppDatabase, $HistoryTableTable> {
  $$HistoryTableTableOrderingComposer({
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

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get poster => $composableBuilder(
    column: $table.poster,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get duration => $composableBuilder(
    column: $table.duration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get watchedSeconds => $composableBuilder(
    column: $table.watchedSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episodeIndex => $composableBuilder(
    column: $table.episodeIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seriesId => $composableBuilder(
    column: $table.seriesId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get watchedAt => $composableBuilder(
    column: $table.watchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HistoryTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $HistoryTableTable> {
  $$HistoryTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get poster =>
      $composableBuilder(column: $table.poster, builder: (column) => column);

  GeneratedColumn<double> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<double> get duration =>
      $composableBuilder(column: $table.duration, builder: (column) => column);

  GeneratedColumn<int> get watchedSeconds => $composableBuilder(
    column: $table.watchedSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get episodeIndex => $composableBuilder(
    column: $table.episodeIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

  GeneratedColumn<int> get watchedAt =>
      $composableBuilder(column: $table.watchedAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get extra =>
      $composableBuilder(column: $table.extra, builder: (column) => column);
}

class $$HistoryTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HistoryTableTable,
          History,
          $$HistoryTableTableFilterComposer,
          $$HistoryTableTableOrderingComposer,
          $$HistoryTableTableAnnotationComposer,
          $$HistoryTableTableCreateCompanionBuilder,
          $$HistoryTableTableUpdateCompanionBuilder,
          (History, BaseReferences<_$AppDatabase, $HistoryTableTable, History>),
          History,
          PrefetchHooks Function()
        > {
  $$HistoryTableTableTableManager(_$AppDatabase db, $HistoryTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HistoryTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HistoryTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HistoryTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> sourceKind = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                Value<String?> poster = const Value.absent(),
                Value<double> position = const Value.absent(),
                Value<double> duration = const Value.absent(),
                Value<int> watchedSeconds = const Value.absent(),
                Value<int?> episodeIndex = const Value.absent(),
                Value<String?> seriesId = const Value.absent(),
                Value<int> watchedAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String?> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HistoryTableCompanion(
                id: id,
                title: title,
                url: url,
                sourceKind: sourceKind,
                sourceId: sourceId,
                poster: poster,
                position: position,
                duration: duration,
                watchedSeconds: watchedSeconds,
                episodeIndex: episodeIndex,
                seriesId: seriesId,
                watchedAt: watchedAt,
                createdAt: createdAt,
                extra: extra,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String url,
                required String sourceKind,
                Value<String?> sourceId = const Value.absent(),
                Value<String?> poster = const Value.absent(),
                Value<double> position = const Value.absent(),
                Value<double> duration = const Value.absent(),
                Value<int> watchedSeconds = const Value.absent(),
                Value<int?> episodeIndex = const Value.absent(),
                Value<String?> seriesId = const Value.absent(),
                required int watchedAt,
                required int createdAt,
                Value<String?> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HistoryTableCompanion.insert(
                id: id,
                title: title,
                url: url,
                sourceKind: sourceKind,
                sourceId: sourceId,
                poster: poster,
                position: position,
                duration: duration,
                watchedSeconds: watchedSeconds,
                episodeIndex: episodeIndex,
                seriesId: seriesId,
                watchedAt: watchedAt,
                createdAt: createdAt,
                extra: extra,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HistoryTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HistoryTableTable,
      History,
      $$HistoryTableTableFilterComposer,
      $$HistoryTableTableOrderingComposer,
      $$HistoryTableTableAnnotationComposer,
      $$HistoryTableTableCreateCompanionBuilder,
      $$HistoryTableTableUpdateCompanionBuilder,
      (History, BaseReferences<_$AppDatabase, $HistoryTableTable, History>),
      History,
      PrefetchHooks Function()
    >;
typedef $$FavoritesTableCreateCompanionBuilder =
    FavoritesCompanion Function({
      required String id,
      required String title,
      required String url,
      required String sourceKind,
      Value<String?> sourceId,
      Value<String?> poster,
      Value<String?> tag,
      Value<String?> note,
      required int addedAt,
      Value<String?> extra,
      Value<int> rowid,
    });
typedef $$FavoritesTableUpdateCompanionBuilder =
    FavoritesCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> url,
      Value<String> sourceKind,
      Value<String?> sourceId,
      Value<String?> poster,
      Value<String?> tag,
      Value<String?> note,
      Value<int> addedAt,
      Value<String?> extra,
      Value<int> rowid,
    });

class $$FavoritesTableFilterComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableFilterComposer({
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

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get poster => $composableBuilder(
    column: $table.poster,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FavoritesTableOrderingComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableOrderingComposer({
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

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get poster => $composableBuilder(
    column: $table.poster,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FavoritesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FavoritesTable> {
  $$FavoritesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get poster =>
      $composableBuilder(column: $table.poster, builder: (column) => column);

  GeneratedColumn<String> get tag =>
      $composableBuilder(column: $table.tag, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<String> get extra =>
      $composableBuilder(column: $table.extra, builder: (column) => column);
}

class $$FavoritesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FavoritesTable,
          Favorite,
          $$FavoritesTableFilterComposer,
          $$FavoritesTableOrderingComposer,
          $$FavoritesTableAnnotationComposer,
          $$FavoritesTableCreateCompanionBuilder,
          $$FavoritesTableUpdateCompanionBuilder,
          (Favorite, BaseReferences<_$AppDatabase, $FavoritesTable, Favorite>),
          Favorite,
          PrefetchHooks Function()
        > {
  $$FavoritesTableTableManager(_$AppDatabase db, $FavoritesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavoritesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavoritesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavoritesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> sourceKind = const Value.absent(),
                Value<String?> sourceId = const Value.absent(),
                Value<String?> poster = const Value.absent(),
                Value<String?> tag = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<String?> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoritesCompanion(
                id: id,
                title: title,
                url: url,
                sourceKind: sourceKind,
                sourceId: sourceId,
                poster: poster,
                tag: tag,
                note: note,
                addedAt: addedAt,
                extra: extra,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String url,
                required String sourceKind,
                Value<String?> sourceId = const Value.absent(),
                Value<String?> poster = const Value.absent(),
                Value<String?> tag = const Value.absent(),
                Value<String?> note = const Value.absent(),
                required int addedAt,
                Value<String?> extra = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoritesCompanion.insert(
                id: id,
                title: title,
                url: url,
                sourceKind: sourceKind,
                sourceId: sourceId,
                poster: poster,
                tag: tag,
                note: note,
                addedAt: addedAt,
                extra: extra,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FavoritesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FavoritesTable,
      Favorite,
      $$FavoritesTableFilterComposer,
      $$FavoritesTableOrderingComposer,
      $$FavoritesTableAnnotationComposer,
      $$FavoritesTableCreateCompanionBuilder,
      $$FavoritesTableUpdateCompanionBuilder,
      (Favorite, BaseReferences<_$AppDatabase, $FavoritesTable, Favorite>),
      Favorite,
      PrefetchHooks Function()
    >;
typedef $$SourcesTableCreateCompanionBuilder =
    SourcesCompanion Function({
      required String id,
      required String name,
      required String kind,
      Value<String?> apiUrl,
      Value<String?> baseUrl,
      Value<String?> username,
      Value<int> enabled,
      Value<int> priority,
      Value<String> health,
      Value<int?> lastCheckAt,
      Value<int?> lastLatencyMs,
      Value<String?> config,
      Value<String?> ext,
      Value<int> unreachable,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$SourcesTableUpdateCompanionBuilder =
    SourcesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> kind,
      Value<String?> apiUrl,
      Value<String?> baseUrl,
      Value<String?> username,
      Value<int> enabled,
      Value<int> priority,
      Value<String> health,
      Value<int?> lastCheckAt,
      Value<int?> lastLatencyMs,
      Value<String?> config,
      Value<String?> ext,
      Value<int> unreachable,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$SourcesTableFilterComposer
    extends Composer<_$AppDatabase, $SourcesTable> {
  $$SourcesTableFilterComposer({
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

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get apiUrl => $composableBuilder(
    column: $table.apiUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get health => $composableBuilder(
    column: $table.health,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastCheckAt => $composableBuilder(
    column: $table.lastCheckAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastLatencyMs => $composableBuilder(
    column: $table.lastLatencyMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get config => $composableBuilder(
    column: $table.config,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ext => $composableBuilder(
    column: $table.ext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreachable => $composableBuilder(
    column: $table.unreachable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SourcesTableOrderingComposer
    extends Composer<_$AppDatabase, $SourcesTable> {
  $$SourcesTableOrderingComposer({
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

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get apiUrl => $composableBuilder(
    column: $table.apiUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseUrl => $composableBuilder(
    column: $table.baseUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get health => $composableBuilder(
    column: $table.health,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastCheckAt => $composableBuilder(
    column: $table.lastCheckAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastLatencyMs => $composableBuilder(
    column: $table.lastLatencyMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get config => $composableBuilder(
    column: $table.config,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ext => $composableBuilder(
    column: $table.ext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreachable => $composableBuilder(
    column: $table.unreachable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SourcesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SourcesTable> {
  $$SourcesTableAnnotationComposer({
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

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get apiUrl =>
      $composableBuilder(column: $table.apiUrl, builder: (column) => column);

  GeneratedColumn<String> get baseUrl =>
      $composableBuilder(column: $table.baseUrl, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<int> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get health =>
      $composableBuilder(column: $table.health, builder: (column) => column);

  GeneratedColumn<int> get lastCheckAt => $composableBuilder(
    column: $table.lastCheckAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastLatencyMs => $composableBuilder(
    column: $table.lastLatencyMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get config =>
      $composableBuilder(column: $table.config, builder: (column) => column);

  GeneratedColumn<String> get ext =>
      $composableBuilder(column: $table.ext, builder: (column) => column);

  GeneratedColumn<int> get unreachable => $composableBuilder(
    column: $table.unreachable,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SourcesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SourcesTable,
          Source,
          $$SourcesTableFilterComposer,
          $$SourcesTableOrderingComposer,
          $$SourcesTableAnnotationComposer,
          $$SourcesTableCreateCompanionBuilder,
          $$SourcesTableUpdateCompanionBuilder,
          (Source, BaseReferences<_$AppDatabase, $SourcesTable, Source>),
          Source,
          PrefetchHooks Function()
        > {
  $$SourcesTableTableManager(_$AppDatabase db, $SourcesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SourcesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> apiUrl = const Value.absent(),
                Value<String?> baseUrl = const Value.absent(),
                Value<String?> username = const Value.absent(),
                Value<int> enabled = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String> health = const Value.absent(),
                Value<int?> lastCheckAt = const Value.absent(),
                Value<int?> lastLatencyMs = const Value.absent(),
                Value<String?> config = const Value.absent(),
                Value<String?> ext = const Value.absent(),
                Value<int> unreachable = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourcesCompanion(
                id: id,
                name: name,
                kind: kind,
                apiUrl: apiUrl,
                baseUrl: baseUrl,
                username: username,
                enabled: enabled,
                priority: priority,
                health: health,
                lastCheckAt: lastCheckAt,
                lastLatencyMs: lastLatencyMs,
                config: config,
                ext: ext,
                unreachable: unreachable,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String kind,
                Value<String?> apiUrl = const Value.absent(),
                Value<String?> baseUrl = const Value.absent(),
                Value<String?> username = const Value.absent(),
                Value<int> enabled = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String> health = const Value.absent(),
                Value<int?> lastCheckAt = const Value.absent(),
                Value<int?> lastLatencyMs = const Value.absent(),
                Value<String?> config = const Value.absent(),
                Value<String?> ext = const Value.absent(),
                Value<int> unreachable = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => SourcesCompanion.insert(
                id: id,
                name: name,
                kind: kind,
                apiUrl: apiUrl,
                baseUrl: baseUrl,
                username: username,
                enabled: enabled,
                priority: priority,
                health: health,
                lastCheckAt: lastCheckAt,
                lastLatencyMs: lastLatencyMs,
                config: config,
                ext: ext,
                unreachable: unreachable,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SourcesTable,
      Source,
      $$SourcesTableFilterComposer,
      $$SourcesTableOrderingComposer,
      $$SourcesTableAnnotationComposer,
      $$SourcesTableCreateCompanionBuilder,
      $$SourcesTableUpdateCompanionBuilder,
      (Source, BaseReferences<_$AppDatabase, $SourcesTable, Source>),
      Source,
      PrefetchHooks Function()
    >;
typedef $$AccountsTableCreateCompanionBuilder =
    AccountsCompanion Function({
      required String id,
      required String kind,
      required String displayName,
      Value<String?> username,
      Value<String?> extra,
      Value<String> status,
      Value<int?> lastVerified,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$AccountsTableUpdateCompanionBuilder =
    AccountsCompanion Function({
      Value<String> id,
      Value<String> kind,
      Value<String> displayName,
      Value<String?> username,
      Value<String?> extra,
      Value<String> status,
      Value<int?> lastVerified,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$AccountsTableFilterComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableFilterComposer({
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

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastVerified => $composableBuilder(
    column: $table.lastVerified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AccountsTableOrderingComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableOrderingComposer({
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

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastVerified => $composableBuilder(
    column: $table.lastVerified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AccountsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get extra =>
      $composableBuilder(column: $table.extra, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get lastVerified => $composableBuilder(
    column: $table.lastVerified,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$AccountsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AccountsTable,
          Account,
          $$AccountsTableFilterComposer,
          $$AccountsTableOrderingComposer,
          $$AccountsTableAnnotationComposer,
          $$AccountsTableCreateCompanionBuilder,
          $$AccountsTableUpdateCompanionBuilder,
          (Account, BaseReferences<_$AppDatabase, $AccountsTable, Account>),
          Account,
          PrefetchHooks Function()
        > {
  $$AccountsTableTableManager(_$AppDatabase db, $AccountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String?> username = const Value.absent(),
                Value<String?> extra = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> lastVerified = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion(
                id: id,
                kind: kind,
                displayName: displayName,
                username: username,
                extra: extra,
                status: status,
                lastVerified: lastVerified,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kind,
                required String displayName,
                Value<String?> username = const Value.absent(),
                Value<String?> extra = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> lastVerified = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion.insert(
                id: id,
                kind: kind,
                displayName: displayName,
                username: username,
                extra: extra,
                status: status,
                lastVerified: lastVerified,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AccountsTable,
      Account,
      $$AccountsTableFilterComposer,
      $$AccountsTableOrderingComposer,
      $$AccountsTableAnnotationComposer,
      $$AccountsTableCreateCompanionBuilder,
      $$AccountsTableUpdateCompanionBuilder,
      (Account, BaseReferences<_$AppDatabase, $AccountsTable, Account>),
      Account,
      PrefetchHooks Function()
    >;
typedef $$DanmakuCacheTableTableCreateCompanionBuilder =
    DanmakuCacheTableCompanion Function({
      required String mediaId,
      Value<int> episodeIndex,
      required String payload,
      required int count,
      required int fetchedAt,
      required int expiresAt,
      Value<int> rowid,
    });
typedef $$DanmakuCacheTableTableUpdateCompanionBuilder =
    DanmakuCacheTableCompanion Function({
      Value<String> mediaId,
      Value<int> episodeIndex,
      Value<String> payload,
      Value<int> count,
      Value<int> fetchedAt,
      Value<int> expiresAt,
      Value<int> rowid,
    });

class $$DanmakuCacheTableTableFilterComposer
    extends Composer<_$AppDatabase, $DanmakuCacheTableTable> {
  $$DanmakuCacheTableTableFilterComposer({
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

  ColumnFilters<int> get episodeIndex => $composableBuilder(
    column: $table.episodeIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DanmakuCacheTableTableOrderingComposer
    extends Composer<_$AppDatabase, $DanmakuCacheTableTable> {
  $$DanmakuCacheTableTableOrderingComposer({
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

  ColumnOrderings<int> get episodeIndex => $composableBuilder(
    column: $table.episodeIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DanmakuCacheTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $DanmakuCacheTableTable> {
  $$DanmakuCacheTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<int> get episodeIndex => $composableBuilder(
    column: $table.episodeIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get count =>
      $composableBuilder(column: $table.count, builder: (column) => column);

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);
}

class $$DanmakuCacheTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DanmakuCacheTableTable,
          DanmakuRow,
          $$DanmakuCacheTableTableFilterComposer,
          $$DanmakuCacheTableTableOrderingComposer,
          $$DanmakuCacheTableTableAnnotationComposer,
          $$DanmakuCacheTableTableCreateCompanionBuilder,
          $$DanmakuCacheTableTableUpdateCompanionBuilder,
          (
            DanmakuRow,
            BaseReferences<_$AppDatabase, $DanmakuCacheTableTable, DanmakuRow>,
          ),
          DanmakuRow,
          PrefetchHooks Function()
        > {
  $$DanmakuCacheTableTableTableManager(
    _$AppDatabase db,
    $DanmakuCacheTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DanmakuCacheTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DanmakuCacheTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DanmakuCacheTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> mediaId = const Value.absent(),
                Value<int> episodeIndex = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> count = const Value.absent(),
                Value<int> fetchedAt = const Value.absent(),
                Value<int> expiresAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DanmakuCacheTableCompanion(
                mediaId: mediaId,
                episodeIndex: episodeIndex,
                payload: payload,
                count: count,
                fetchedAt: fetchedAt,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mediaId,
                Value<int> episodeIndex = const Value.absent(),
                required String payload,
                required int count,
                required int fetchedAt,
                required int expiresAt,
                Value<int> rowid = const Value.absent(),
              }) => DanmakuCacheTableCompanion.insert(
                mediaId: mediaId,
                episodeIndex: episodeIndex,
                payload: payload,
                count: count,
                fetchedAt: fetchedAt,
                expiresAt: expiresAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DanmakuCacheTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DanmakuCacheTableTable,
      DanmakuRow,
      $$DanmakuCacheTableTableFilterComposer,
      $$DanmakuCacheTableTableOrderingComposer,
      $$DanmakuCacheTableTableAnnotationComposer,
      $$DanmakuCacheTableTableCreateCompanionBuilder,
      $$DanmakuCacheTableTableUpdateCompanionBuilder,
      (
        DanmakuRow,
        BaseReferences<_$AppDatabase, $DanmakuCacheTableTable, DanmakuRow>,
      ),
      DanmakuRow,
      PrefetchHooks Function()
    >;
typedef $$SubtitlesTableCreateCompanionBuilder =
    SubtitlesCompanion Function({
      required String id,
      required String mediaUrl,
      Value<String> lang,
      required String label,
      Value<String?> path,
      Value<String?> url,
      Value<String> format,
      required int addedAt,
      Value<int> lastUsedAt,
      Value<int> rowid,
    });
typedef $$SubtitlesTableUpdateCompanionBuilder =
    SubtitlesCompanion Function({
      Value<String> id,
      Value<String> mediaUrl,
      Value<String> lang,
      Value<String> label,
      Value<String?> path,
      Value<String?> url,
      Value<String> format,
      Value<int> addedAt,
      Value<int> lastUsedAt,
      Value<int> rowid,
    });

class $$SubtitlesTableFilterComposer
    extends Composer<_$AppDatabase, $SubtitlesTable> {
  $$SubtitlesTableFilterComposer({
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

  ColumnFilters<String> get mediaUrl => $composableBuilder(
    column: $table.mediaUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lang => $composableBuilder(
    column: $table.lang,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SubtitlesTableOrderingComposer
    extends Composer<_$AppDatabase, $SubtitlesTable> {
  $$SubtitlesTableOrderingComposer({
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

  ColumnOrderings<String> get mediaUrl => $composableBuilder(
    column: $table.mediaUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lang => $composableBuilder(
    column: $table.lang,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SubtitlesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SubtitlesTable> {
  $$SubtitlesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get mediaUrl =>
      $composableBuilder(column: $table.mediaUrl, builder: (column) => column);

  GeneratedColumn<String> get lang =>
      $composableBuilder(column: $table.lang, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<int> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );
}

class $$SubtitlesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SubtitlesTable,
          SubtitleRow,
          $$SubtitlesTableFilterComposer,
          $$SubtitlesTableOrderingComposer,
          $$SubtitlesTableAnnotationComposer,
          $$SubtitlesTableCreateCompanionBuilder,
          $$SubtitlesTableUpdateCompanionBuilder,
          (
            SubtitleRow,
            BaseReferences<_$AppDatabase, $SubtitlesTable, SubtitleRow>,
          ),
          SubtitleRow,
          PrefetchHooks Function()
        > {
  $$SubtitlesTableTableManager(_$AppDatabase db, $SubtitlesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SubtitlesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SubtitlesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SubtitlesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> mediaUrl = const Value.absent(),
                Value<String> lang = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String?> path = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<String> format = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<int> lastUsedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SubtitlesCompanion(
                id: id,
                mediaUrl: mediaUrl,
                lang: lang,
                label: label,
                path: path,
                url: url,
                format: format,
                addedAt: addedAt,
                lastUsedAt: lastUsedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String mediaUrl,
                Value<String> lang = const Value.absent(),
                required String label,
                Value<String?> path = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<String> format = const Value.absent(),
                required int addedAt,
                Value<int> lastUsedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SubtitlesCompanion.insert(
                id: id,
                mediaUrl: mediaUrl,
                lang: lang,
                label: label,
                path: path,
                url: url,
                format: format,
                addedAt: addedAt,
                lastUsedAt: lastUsedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SubtitlesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SubtitlesTable,
      SubtitleRow,
      $$SubtitlesTableFilterComposer,
      $$SubtitlesTableOrderingComposer,
      $$SubtitlesTableAnnotationComposer,
      $$SubtitlesTableCreateCompanionBuilder,
      $$SubtitlesTableUpdateCompanionBuilder,
      (
        SubtitleRow,
        BaseReferences<_$AppDatabase, $SubtitlesTable, SubtitleRow>,
      ),
      SubtitleRow,
      PrefetchHooks Function()
    >;
typedef $$TagsTableCreateCompanionBuilder =
    TagsCompanion Function({
      required String id,
      required String mediaUrl,
      required String name,
      Value<int> color,
      required int addedAt,
      Value<int> rowid,
    });
typedef $$TagsTableUpdateCompanionBuilder =
    TagsCompanion Function({
      Value<String> id,
      Value<String> mediaUrl,
      Value<String> name,
      Value<int> color,
      Value<int> addedAt,
      Value<int> rowid,
    });

class $$TagsTableFilterComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
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

  ColumnFilters<String> get mediaUrl => $composableBuilder(
    column: $table.mediaUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TagsTableOrderingComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
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

  ColumnOrderings<String> get mediaUrl => $composableBuilder(
    column: $table.mediaUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get mediaUrl =>
      $composableBuilder(column: $table.mediaUrl, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagsTable,
          TagRow,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (TagRow, BaseReferences<_$AppDatabase, $TagsTable, TagRow>),
          TagRow,
          PrefetchHooks Function()
        > {
  $$TagsTableTableManager(_$AppDatabase db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> mediaUrl = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion(
                id: id,
                mediaUrl: mediaUrl,
                name: name,
                color: color,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String mediaUrl,
                required String name,
                Value<int> color = const Value.absent(),
                required int addedAt,
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion.insert(
                id: id,
                mediaUrl: mediaUrl,
                name: name,
                color: color,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagsTable,
      TagRow,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (TagRow, BaseReferences<_$AppDatabase, $TagsTable, TagRow>),
      TagRow,
      PrefetchHooks Function()
    >;
typedef $$SourceRatingsTableCreateCompanionBuilder =
    SourceRatingsCompanion Function({
      required String sourceId,
      required int score,
      required int ratedAt,
      Value<int> rowid,
    });
typedef $$SourceRatingsTableUpdateCompanionBuilder =
    SourceRatingsCompanion Function({
      Value<String> sourceId,
      Value<int> score,
      Value<int> ratedAt,
      Value<int> rowid,
    });

class $$SourceRatingsTableFilterComposer
    extends Composer<_$AppDatabase, $SourceRatingsTable> {
  $$SourceRatingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ratedAt => $composableBuilder(
    column: $table.ratedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SourceRatingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SourceRatingsTable> {
  $$SourceRatingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ratedAt => $composableBuilder(
    column: $table.ratedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SourceRatingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SourceRatingsTable> {
  $$SourceRatingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<int> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<int> get ratedAt =>
      $composableBuilder(column: $table.ratedAt, builder: (column) => column);
}

class $$SourceRatingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SourceRatingsTable,
          SourceRating,
          $$SourceRatingsTableFilterComposer,
          $$SourceRatingsTableOrderingComposer,
          $$SourceRatingsTableAnnotationComposer,
          $$SourceRatingsTableCreateCompanionBuilder,
          $$SourceRatingsTableUpdateCompanionBuilder,
          (
            SourceRating,
            BaseReferences<_$AppDatabase, $SourceRatingsTable, SourceRating>,
          ),
          SourceRating,
          PrefetchHooks Function()
        > {
  $$SourceRatingsTableTableManager(_$AppDatabase db, $SourceRatingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SourceRatingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SourceRatingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SourceRatingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceId = const Value.absent(),
                Value<int> score = const Value.absent(),
                Value<int> ratedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourceRatingsCompanion(
                sourceId: sourceId,
                score: score,
                ratedAt: ratedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceId,
                required int score,
                required int ratedAt,
                Value<int> rowid = const Value.absent(),
              }) => SourceRatingsCompanion.insert(
                sourceId: sourceId,
                score: score,
                ratedAt: ratedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SourceRatingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SourceRatingsTable,
      SourceRating,
      $$SourceRatingsTableFilterComposer,
      $$SourceRatingsTableOrderingComposer,
      $$SourceRatingsTableAnnotationComposer,
      $$SourceRatingsTableCreateCompanionBuilder,
      $$SourceRatingsTableUpdateCompanionBuilder,
      (
        SourceRating,
        BaseReferences<_$AppDatabase, $SourceRatingsTable, SourceRating>,
      ),
      SourceRating,
      PrefetchHooks Function()
    >;
typedef $$PlaylistsTableCreateCompanionBuilder =
    PlaylistsCompanion Function({
      required String id,
      required String name,
      required String mediaUrl,
      Value<String?> mediaTitle,
      Value<int> sortIndex,
      required int addedAt,
      Value<int> rowid,
    });
typedef $$PlaylistsTableUpdateCompanionBuilder =
    PlaylistsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> mediaUrl,
      Value<String?> mediaTitle,
      Value<int> sortIndex,
      Value<int> addedAt,
      Value<int> rowid,
    });

class $$PlaylistsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableFilterComposer({
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

  ColumnFilters<String> get mediaUrl => $composableBuilder(
    column: $table.mediaUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaTitle => $composableBuilder(
    column: $table.mediaTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortIndex => $composableBuilder(
    column: $table.sortIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlaylistsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableOrderingComposer({
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

  ColumnOrderings<String> get mediaUrl => $composableBuilder(
    column: $table.mediaUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaTitle => $composableBuilder(
    column: $table.mediaTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortIndex => $composableBuilder(
    column: $table.sortIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableAnnotationComposer({
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

  GeneratedColumn<String> get mediaUrl =>
      $composableBuilder(column: $table.mediaUrl, builder: (column) => column);

  GeneratedColumn<String> get mediaTitle => $composableBuilder(
    column: $table.mediaTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortIndex =>
      $composableBuilder(column: $table.sortIndex, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$PlaylistsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistsTable,
          Playlist,
          $$PlaylistsTableFilterComposer,
          $$PlaylistsTableOrderingComposer,
          $$PlaylistsTableAnnotationComposer,
          $$PlaylistsTableCreateCompanionBuilder,
          $$PlaylistsTableUpdateCompanionBuilder,
          (Playlist, BaseReferences<_$AppDatabase, $PlaylistsTable, Playlist>),
          Playlist,
          PrefetchHooks Function()
        > {
  $$PlaylistsTableTableManager(_$AppDatabase db, $PlaylistsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> mediaUrl = const Value.absent(),
                Value<String?> mediaTitle = const Value.absent(),
                Value<int> sortIndex = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsCompanion(
                id: id,
                name: name,
                mediaUrl: mediaUrl,
                mediaTitle: mediaTitle,
                sortIndex: sortIndex,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String mediaUrl,
                Value<String?> mediaTitle = const Value.absent(),
                Value<int> sortIndex = const Value.absent(),
                required int addedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlaylistsCompanion.insert(
                id: id,
                name: name,
                mediaUrl: mediaUrl,
                mediaTitle: mediaTitle,
                sortIndex: sortIndex,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlaylistsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistsTable,
      Playlist,
      $$PlaylistsTableFilterComposer,
      $$PlaylistsTableOrderingComposer,
      $$PlaylistsTableAnnotationComposer,
      $$PlaylistsTableCreateCompanionBuilder,
      $$PlaylistsTableUpdateCompanionBuilder,
      (Playlist, BaseReferences<_$AppDatabase, $PlaylistsTable, Playlist>),
      Playlist,
      PrefetchHooks Function()
    >;
typedef $$ChapterMarksTableCreateCompanionBuilder =
    ChapterMarksCompanion Function({
      required String mediaId,
      Value<double> introEnd,
      Value<double> outroStart,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ChapterMarksTableUpdateCompanionBuilder =
    ChapterMarksCompanion Function({
      Value<String> mediaId,
      Value<double> introEnd,
      Value<double> outroStart,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ChapterMarksTableFilterComposer
    extends Composer<_$AppDatabase, $ChapterMarksTable> {
  $$ChapterMarksTableFilterComposer({
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

  ColumnFilters<double> get introEnd => $composableBuilder(
    column: $table.introEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get outroStart => $composableBuilder(
    column: $table.outroStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChapterMarksTableOrderingComposer
    extends Composer<_$AppDatabase, $ChapterMarksTable> {
  $$ChapterMarksTableOrderingComposer({
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

  ColumnOrderings<double> get introEnd => $composableBuilder(
    column: $table.introEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get outroStart => $composableBuilder(
    column: $table.outroStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChapterMarksTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChapterMarksTable> {
  $$ChapterMarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mediaId =>
      $composableBuilder(column: $table.mediaId, builder: (column) => column);

  GeneratedColumn<double> get introEnd =>
      $composableBuilder(column: $table.introEnd, builder: (column) => column);

  GeneratedColumn<double> get outroStart => $composableBuilder(
    column: $table.outroStart,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ChapterMarksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChapterMarksTable,
          ChapterMark,
          $$ChapterMarksTableFilterComposer,
          $$ChapterMarksTableOrderingComposer,
          $$ChapterMarksTableAnnotationComposer,
          $$ChapterMarksTableCreateCompanionBuilder,
          $$ChapterMarksTableUpdateCompanionBuilder,
          (
            ChapterMark,
            BaseReferences<_$AppDatabase, $ChapterMarksTable, ChapterMark>,
          ),
          ChapterMark,
          PrefetchHooks Function()
        > {
  $$ChapterMarksTableTableManager(_$AppDatabase db, $ChapterMarksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChapterMarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChapterMarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChapterMarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> mediaId = const Value.absent(),
                Value<double> introEnd = const Value.absent(),
                Value<double> outroStart = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChapterMarksCompanion(
                mediaId: mediaId,
                introEnd: introEnd,
                outroStart: outroStart,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mediaId,
                Value<double> introEnd = const Value.absent(),
                Value<double> outroStart = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ChapterMarksCompanion.insert(
                mediaId: mediaId,
                introEnd: introEnd,
                outroStart: outroStart,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChapterMarksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChapterMarksTable,
      ChapterMark,
      $$ChapterMarksTableFilterComposer,
      $$ChapterMarksTableOrderingComposer,
      $$ChapterMarksTableAnnotationComposer,
      $$ChapterMarksTableCreateCompanionBuilder,
      $$ChapterMarksTableUpdateCompanionBuilder,
      (
        ChapterMark,
        BaseReferences<_$AppDatabase, $ChapterMarksTable, ChapterMark>,
      ),
      ChapterMark,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$RoomsTableTableManager get rooms =>
      $$RoomsTableTableManager(_db, _db.rooms);
  $$HistoryTableTableTableManager get historyTable =>
      $$HistoryTableTableTableManager(_db, _db.historyTable);
  $$FavoritesTableTableManager get favorites =>
      $$FavoritesTableTableManager(_db, _db.favorites);
  $$SourcesTableTableManager get sources =>
      $$SourcesTableTableManager(_db, _db.sources);
  $$AccountsTableTableManager get accounts =>
      $$AccountsTableTableManager(_db, _db.accounts);
  $$DanmakuCacheTableTableTableManager get danmakuCacheTable =>
      $$DanmakuCacheTableTableTableManager(_db, _db.danmakuCacheTable);
  $$SubtitlesTableTableManager get subtitles =>
      $$SubtitlesTableTableManager(_db, _db.subtitles);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$SourceRatingsTableTableManager get sourceRatings =>
      $$SourceRatingsTableTableManager(_db, _db.sourceRatings);
  $$PlaylistsTableTableManager get playlists =>
      $$PlaylistsTableTableManager(_db, _db.playlists);
  $$ChapterMarksTableTableManager get chapterMarks =>
      $$ChapterMarksTableTableManager(_db, _db.chapterMarks);
}

mixin _$RoomDaoMixin on DatabaseAccessor<AppDatabase> {
  $RoomsTable get rooms => attachedDatabase.rooms;
}
mixin _$HistoryDaoMixin on DatabaseAccessor<AppDatabase> {
  $HistoryTableTable get historyTable => attachedDatabase.historyTable;
}
mixin _$FavoriteDaoMixin on DatabaseAccessor<AppDatabase> {
  $FavoritesTable get favorites => attachedDatabase.favorites;
}
mixin _$SourceDaoMixin on DatabaseAccessor<AppDatabase> {
  $SourcesTable get sources => attachedDatabase.sources;
}
mixin _$AccountDaoMixin on DatabaseAccessor<AppDatabase> {
  $AccountsTable get accounts => attachedDatabase.accounts;
}
mixin _$DanmakuDaoMixin on DatabaseAccessor<AppDatabase> {
  $DanmakuCacheTableTable get danmakuCacheTable =>
      attachedDatabase.danmakuCacheTable;
}
