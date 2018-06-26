import 'dart:async';

import '../db.dart';
import '../query/mixin.dart';
import 'query_builder.dart';
import 'postgresql_query_reduce.dart';

class PostgresQuery<InstanceType extends ManagedObject> extends Object
    with QueryMixin<InstanceType>
    implements Query<InstanceType> {
  PostgresQuery(this.context);

  PostgresQuery.withEntity(this.context, ManagedEntity entity) {
    _entity = entity;
  }

  @override
  ManagedContext context;

  @override
  ManagedEntity get entity => _entity ?? context.dataModel.entityForType(InstanceType);

  ManagedEntity _entity;

  @override
  QueryReduceOperation<InstanceType> get reduce {
    return new PostgresQueryReduce(this);
  }

  @override
  Future<InstanceType> insert() async {
    validateInput(ValidateOperation.insert);

    var builder = new PostgresQueryBuilder(this);

    var buffer = new StringBuffer();
    buffer.write("INSERT INTO ${builder.sqlTableName} ");

    if (builder.columnValueBuilders.isEmpty) {
      buffer.write("VALUES (DEFAULT) ");
    } else {
      buffer.write("(${builder.sqlColumnsToInsert}) ");
      buffer.write("VALUES (${builder.sqlValuesToInsert}) ");
    }

    if ((builder.returning?.length ?? 0) > 0) {
      buffer.write("RETURNING ${builder.sqlColumnsToReturn}");
    }

    var results =
        await context.persistentStore.executeQuery(buffer.toString(), builder.variables, timeoutInSeconds);

    return builder.instancesForRows(results).first;
  }

  @override
  Future<List<InstanceType>> update() async {
    validateInput(ValidateOperation.update);

    var builder = new PostgresQueryBuilder(this);

    var buffer = new StringBuffer();
    buffer.write("UPDATE ${builder.sqlTableName} ");
    buffer.write("SET ${builder.sqlColumnsAndValuesToUpdate} ");

    if (builder.sqlWhereClause != null) {
      buffer.write("WHERE ${builder.sqlWhereClause} ");
    } else if (!canModifyAllInstances) {
      throw canModifyAllInstancesError;
    }

    if ((builder.returning?.length ?? 0) > 0) {
      buffer.write("RETURNING ${builder.sqlColumnsToReturn}");
    }

    var results =
        await context.persistentStore.executeQuery(buffer.toString(), builder.variables, timeoutInSeconds);

    return builder.instancesForRows(results);
  }

  @override
  Future<InstanceType> updateOne() async {
    var results = await update();
    if (results.length == 1) {
      return results.first;
    } else if (results.length == 0) {
      return null;
    }

    throw new StateError("Query error. 'updateOne' modified more than one row in '${entity.tableName}'. "
            "This was likely unintended and may be indicativate of a more serious error. Query "
            "should add 'where' constraints on a unique column.");
  }

  @override
  Future<int> delete() async {
    var builder = new PostgresQueryBuilder(this);

    var buffer = new StringBuffer();
    buffer.write("DELETE FROM ${builder.sqlTableName} ");

    if (builder.sqlWhereClause != null) {
      buffer.write("WHERE ${builder.sqlWhereClause} ");
    } else if (!canModifyAllInstances) {
      throw canModifyAllInstancesError;
    }

    final result = await context.persistentStore.executeQuery(buffer.toString(), builder.variables, timeoutInSeconds,
        returnType: PersistentStoreQueryReturnType.rowCount);
    return result as int;
  }

  @override
  Future<InstanceType> fetchOne() async {
    var builder = createFetchBuilder();

    if (!builder.containsJoins) {
      fetchLimit = 1;
    }

    var results = await _fetch(builder);
    if (results.length == 1) {
      return results.first;
    } else if (results.length > 1) {
      throw new StateError("Query error. 'fetchOne' returned more than one row from '${entity.tableName}'. "
          "This was likely unintended and may be indicativate of a more serious error. Query "
          "should add 'where' constraints on a unique column.");
    }

    return null;
  }

  @override
  Future<List<InstanceType>> fetch() async {
    return _fetch(createFetchBuilder());
  }

  //////

  PostgresQueryBuilder createFetchBuilder() {
    var builder = new PostgresQueryBuilder(this);

    if (pageDescriptor != null) {
      validatePageDescriptor();
    }

    if (builder.containsJoins && pageDescriptor != null) {
      throw new StateError("Invalid query. Cannot set both 'pageDescription' and use 'join' in query.");
    }

    return builder;
  }

  Future<List<InstanceType>> _fetch(PostgresQueryBuilder builder) async {
    var buffer = new StringBuffer();
    buffer.write("SELECT ${builder.sqlColumnsToReturn} ");
    buffer.write("FROM ${builder.sqlTableName} ");

    if (builder.containsJoins) {
      buffer.write("${builder.sqlJoin} ");
    }

    if (builder.sqlWhereClause != null) {
      buffer.write("WHERE ${builder.sqlWhereClause} ");
    }

    buffer.write("${builder.sqlOrderBy} ");

    if (fetchLimit != 0) {
      buffer.write("LIMIT $fetchLimit ");
    }

    if (offset != 0) {
      buffer.write("OFFSET $offset ");
    }

    var results =
        await context.persistentStore.executeQuery(buffer.toString(), builder.variables, timeoutInSeconds);

    return builder.instancesForRows(results);
  }

  void validatePageDescriptor() {
    var prop = entity.attributes[pageDescriptor.propertyName];
    if (prop == null) {
      throw new StateError("Invalid query page descriptor. Column '${pageDescriptor.propertyName}' does not exist for table '${entity.tableName}'");
    }

    if (pageDescriptor.boundingValue != null && !prop.isAssignableWith(pageDescriptor.boundingValue)) {
      throw new StateError("Invalid query page descriptor. Bounding value for column '${pageDescriptor.propertyName}' has invalid type.");
    }
  }

  static final StateError canModifyAllInstancesError = new StateError(
      "Invalid Query<T>. Query is either update or delete query with no WHERE clause. To confirm this query is correct, set 'canModifyAllInstances' to true.");
}
