import 'package:sqflite/sqflite.dart';

final String tableConfig = "config";
final String configId = "id";
final String configName = "name";
final String configOpen = "open";
final String configClose = "close";
final String configCapturing = "capturing";
final String configRTMPIPEndpoint = "RTMPIPEndpoint";

class Config {
  late int id;
  late String name;
  late int openHour;
  late int closeHour;
  late bool capturing;
  late String RTMPIPEndpoint;

  Config(this.id, this.name, this.openHour, this.closeHour, this.capturing, this.RTMPIPEndpoint);

  Map<String, dynamic> toMap() {
    var map = <String, dynamic>{
      configName: name,
      configOpen: openHour,
      configClose: closeHour,
      configCapturing: capturing == true ? 1 : 0,
      configRTMPIPEndpoint: RTMPIPEndpoint
    };
    if (id != null) {
      map[configId] = id;
    }
    return map;
  }

  Config.fromMap(Map<String, dynamic> map) {
    id = map[configId];
    name = map[configName];
    openHour = map[configOpen];
    closeHour = map[configClose];
    capturing = map[configCapturing] == 1;
    RTMPIPEndpoint = map[configRTMPIPEndpoint];
  }

  @override
  String toString() {
    // TODO: implement toString
    String text =
        "id: ${this.id}, name: ${this.name}, openHour: ${this.openHour}," +
        "closeHour: ${closeHour}, capturing: ${this.capturing}" + 
        "RTMPIPEndpoint: ${RTMPIPEndpoint}";
    print(text);

    return text;
  }
}

class ConfigProvider {
  late Database db;

  Future open() async {
    db = await openDatabase("store.db", version: 1,
        onCreate: (Database db, int version) async {
      await db.execute(
          "CREATE TABLE config (id INTEGER AUTO INCREMENT, name TEXT, open INTEGER, close INTEGER, capturing BOOL, RTMPIPEndpoint TEXT)");

      int initialId = await db.insert("config",
          {"name": "nueva_tienda", "open": 12, "close": 12, "capturing": 0, "RTMPIPEndpoint": "111.222.33.44"});

      print("initialId: ${initialId}");
    });
  }

  Future<Config> insert(Config config) async {
    config.id = await db.insert(tableConfig, config.toMap());
    return config;
  }

  Future<Config> getConfig(int id) async {
    List<Map<String, dynamic>> results =
        await db.query("config", where: 'id = ?', whereArgs: [1]);

    if (results.isEmpty) {
      Config config = Config(5, "empty", 0, 0, false, "111.222.33.44");

      return config;
    }

    return Config.fromMap(results.first);
  }

  Future<int> delete(int id) async {
    return await db
        .delete(tableConfig, where: '$configId = ?', whereArgs: [id]);
  }

  Future<int> update(Config config) async {
    return await db.update(tableConfig, config.toMap(),
        where: '$configId = ?', whereArgs: [config.id]);
  }

  Future close() async => db.close();
}
