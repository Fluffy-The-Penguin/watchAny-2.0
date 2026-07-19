import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// Helper to convert hex to bytes
List<int> hexToBytes(String hex) {
  var bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return bytes;
}

// UDP scrape implementation
Future<Map<String, int>?> scrapeUdp(String trackerHost, int trackerPort, String infoHashHex) async {
  RawDatagramSocket? socket;
  try {
    final addresses = await InternetAddress.lookup(trackerHost);
    final ipv4Addresses = addresses.where((a) => a.type == InternetAddressType.IPv4);
    if (ipv4Addresses.isEmpty) return null;
    final address = ipv4Addresses.first;

    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.readEventsEnabled = true;

    final rand = Random();
    final transactionId = rand.nextInt(0xFFFFFFFF);

    // 1. Send Connect request
    // Size: 16 bytes
    // offset 0: connection_id (8 bytes: 0x41727101980)
    // offset 8: action (4 bytes: 0 for connect)
    // offset 12: transaction_id (4 bytes)
    final connectData = ByteData(16);
    // connection_id: 0x41727101980 -> high 4 bytes: 0x00000417, low 4 bytes: 0x27101980
    connectData.setUint32(0, 0x00000417, Endian.big);
    connectData.setUint32(4, 0x27101980, Endian.big);
    connectData.setUint32(8, 0, Endian.big);
    connectData.setUint32(12, transactionId, Endian.big);

    socket.send(connectData.buffer.asUint8List(), address, trackerPort);

    // Wait for connect response
    Uint8List? connectResponse;
    var completer = Completer<Uint8List?>();
    StreamSubscription? sub;
    sub = socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = socket!.receive();
        if (dg != null) {
          completer.complete(dg.data);
        }
      }
    });

    connectResponse = await completer.future.timeout(const Duration(seconds: 3), onTimeout: () => null);
    await sub.cancel();
    if (connectResponse == null || connectResponse.length < 16) {
      return null;
    }

    final connectResData = ByteData.sublistView(connectResponse);
    final action = connectResData.getUint32(0, Endian.big);
    final resTxId = connectResData.getUint32(4, Endian.big);
    if (action != 0 || resTxId != transactionId) {
      return null;
    }

    final connectionIdHigh = connectResData.getUint32(8, Endian.big);
    final connectionIdLow = connectResData.getUint32(12, Endian.big);

    // 2. Send Scrape request
    // Size: 16 + 20 = 36 bytes
    // offset 0: connection_id (8 bytes)
    // offset 8: action (4 bytes: 2 for scrape)
    // offset 12: transaction_id (4 bytes)
    // offset 16: info_hash (20 bytes)
    final scrapeTxId = rand.nextInt(0xFFFFFFFF);
    final scrapeData = ByteData(36);
    scrapeData.setUint32(0, connectionIdHigh, Endian.big);
    scrapeData.setUint32(4, connectionIdLow, Endian.big);
    scrapeData.setUint32(8, 2, Endian.big);
    scrapeData.setUint32(12, scrapeTxId, Endian.big);

    final hashBytes = hexToBytes(infoHashHex);
    for (var i = 0; i < 20; i++) {
      scrapeData.setUint8(16 + i, hashBytes[i]);
    }

    socket.send(scrapeData.buffer.asUint8List(), address, trackerPort);

    // Wait for scrape response
    Uint8List? scrapeResponse;
    completer = Completer<Uint8List?>();
    sub = socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = socket!.receive();
        if (dg != null) {
          completer.complete(dg.data);
        }
      }
    });

    scrapeResponse = await completer.future.timeout(const Duration(seconds: 3), onTimeout: () => null);
    await sub.cancel();
    if (scrapeResponse == null || scrapeResponse.length < 20) {
      return null;
    }

    final scrapeResData = ByteData.sublistView(scrapeResponse);
    final scrapeAction = scrapeResData.getUint32(0, Endian.big);
    final scrapeResTxId = scrapeResData.getUint32(4, Endian.big);
    if (scrapeAction != 2 || scrapeResTxId != scrapeTxId) {
      return null;
    }

    final seeders = scrapeResData.getUint32(8, Endian.big);
    final completed = scrapeResData.getUint32(12, Endian.big);
    final leechers = scrapeResData.getUint32(16, Endian.big);

    return {'seeders': seeders, 'peers': leechers, 'completed': completed};
  } catch (e) {
    print('Scrape error: $e');
    return null;
  } finally {
    socket?.close();
  }
}

void main() async {
  final hash = '1f20d43befcd464490bef52d6c66515aa85977e2';
  // Try opentrackr
  print('Scraping opentrackr...');
  final res1 = await scrapeUdp('tracker.opentrackr.org', 1337, hash);
  print('Result opentrackr: $res1');

  // Try moeking
  print('Scraping moeking...');
  final res2 = await scrapeUdp('tracker.moeking.me', 6969, hash);
  print('Result moeking: $res2');
}
