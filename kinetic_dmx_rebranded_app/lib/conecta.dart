import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'main.dart';
import 'motor_sinetico_page.dart';

class ConectaPage extends StatefulWidget {
  final BleDevice? activeDevice;
  const ConectaPage({super.key, this.activeDevice});

  @override
  State<ConectaPage> createState() => _ConectaPageState();
}

class _ConectaPageState extends State<ConectaPage> {
  bool _isCarregando = false;
  bool _isConectado = false;
  bool _autenticado = false;
  BleDevice? _deviceAlvo;
  String _buffer = "";

  final String _serviceUuid = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  final String _txUuid = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
  final String _rxUuid = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";

  List<BleDevice> dispositivosPareados = [];
  BleDevice? dispositivoSelecionado;

  List<Map<String, dynamic>> aparelhosRDMDescobertos = [];

  @override
  void initState() {
    super.initState();
    _configurarEscutaBLEConecta();

    if (widget.activeDevice != null) {
      _deviceAlvo = widget.activeDevice;
      _isConectado = true;
      _autenticado = true;
      _isCarregando = false;
      Future.delayed(const Duration(milliseconds: 500), () {
        _enviarComando("VARREDURA_RDM", "1");
        _mostrarFeedback("Buscando dispositivos RDM...");
      });
    } else {
      _iniciarDescobertaAutomatica();
    }
  }

  void _configurarEscutaBLEConecta() {
    UniversalBle.onValueChange = (String dId, String cId, Uint8List val, int? timestamp) {
      if (_deviceAlvo != null && dId == _deviceAlvo!.deviceId) {
        _buffer += utf8.decode(val);
        while (_buffer.contains('\n')) {
          int pos = _buffer.indexOf('\n');
          String linha = _buffer.substring(0, pos).trim();
          _buffer = _buffer.substring(pos + 1);
          if (linha.isEmpty) continue;

          print("📝 Rebranded Conecta recebido: $linha");

          if (linha.startsWith("AUTH_CHALLENGE:")) {
            int challenge = int.tryParse(linha.split(":")[1]) ?? 0;
            int response = (challenge * 2) + 7;
            _enviarComando("AUTH_RESPONSE", "$response");
          } else if (linha.contains("MILETO_AUTH:VALID")) {
            setState(() {
              _autenticado = true;
            });
            _mostrarFeedback("Console Autenticado! Escaneando linha DMX...");
            _enviarComando("VARREDURA_RDM", "1");
          } else if (linha == "RDM_START") {
            setState(() {
              aparelhosRDMDescobertos.clear();
            });
          } else if (linha.startsWith("RDM_DEV:")) {
            String dados = linha.replaceAll("RDM_DEV:", "");
            List<String> partes = dados.split(",");
            if (partes.length >= 5) {
              String uidCompleto = "${partes[0].toUpperCase()}:${partes[1].toUpperCase()}";
              String modelName = partes[4].toUpperCase();

              setState(() {
                aparelhosRDMDescobertos.add({
                  "uid": uidCompleto,
                  "nome": partes[4].replaceAll("_", " "),
                  "dmx": int.tryParse(partes[2]) ?? 1,
                  "canais": int.tryParse(partes[3]) ?? 1,
                  "modelo": modelName,
                });
              });
            }
          } else if (linha == "RDM_END") {
            _mostrarFeedback("Equipamentos encontrados!");
          }
        }
      }
    };

    UniversalBle.onConnectionChange = (String dId, bool isConnected, String? error) {
      if (_deviceAlvo != null && dId == _deviceAlvo!.deviceId) {
        setState(() {
          _isConectado = isConnected;
          if (!isConnected) {
            _deviceAlvo = null;
            _autenticado = false;
            aparelhosRDMDescobertos.clear();
          }
        });
      }
    };
  }

  void _abrirPainelDoEquipamento(Map<String, dynamic> aparelho) {
    _mostrarFeedback("Abrindo Painel para ${aparelho['nome']}...");
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeScreen(deviceAlvo: _deviceAlvo, abaInicial: 0),
      ),
    );
  }

  Future<void> _iniciarDescobertaAutomatica() async {
    setState(() {
      _isCarregando = true;
      _isConectado = false;
      _autenticado = false;
      aparelhosRDMDescobertos.clear();
      dispositivosPareados.clear();
    });

    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location,
    ].request();

    if (statuses[Permission.bluetoothScan]?.isGranted != true || statuses[Permission.bluetoothConnect]?.isGranted != true) {
      setState(() { _isCarregando = false; });
      _mostrarFeedback("⚠️ Permissões necessárias.");
      return;
    }

    try {
      await UniversalBle.startScan();

      Completer<BleDevice> c = Completer();
      UniversalBle.onScanResult = (device) {
        if (device.name != null && !dispositivosPareados.any((d) => d.deviceId == device.deviceId)) {
          setState(() {
            dispositivosPareados.add(device);
          });
        }
        String name = device.name ?? '';
        if (name.toUpperCase().contains("KINETIC") || name.toUpperCase().contains("MILETO")) {
          _deviceAlvo = device;
          if (!c.isCompleted) c.complete(device);
        }
      };

      _deviceAlvo = await c.future.timeout(const Duration(seconds: 8));
      await UniversalBle.stopScan();

      if (_deviceAlvo != null) {
        await _conectarAoDispositivo(_deviceAlvo!);
      }
    } catch (e) {
      try { await UniversalBle.stopScan(); } catch (_) {}
      setState(() { _isCarregando = false; });
      _mostrarFeedback("Dispositivo não encontrado automaticamente. Conecte manualmente.");
    }
  }

  Future<void> _conectarAoDispositivo(BleDevice device) async {
    setState(() {
      _isCarregando = true;
      _deviceAlvo = device;
    });

    try {
      await UniversalBle.connect(device.deviceId);
      await Future.delayed(const Duration(milliseconds: 800));
      try {
        await UniversalBle.requestMtu(device.deviceId, 251);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
      await UniversalBle.discoverServices(device.deviceId);
      await UniversalBle.setNotifiable(device.deviceId, _serviceUuid, _txUuid, BleInputProperty.notification);

      setState(() {
        _isConectado = true;
        _isCarregando = false;
      });
    } catch (e) {
      setState(() {
        _isConectado = false;
        _isCarregando = false;
        _deviceAlvo = null;
      });
      _mostrarFeedback("Falha ao conectar.");
    }
  }

  void _enviarComando(String cmd, String val) async {
    if (_isConectado && _deviceAlvo != null) {
      String data = "$cmd:$val\n";
      Uint8List bytes = Uint8List.fromList(utf8.encode(data));
      try {
        await UniversalBle.writeValue(_deviceAlvo!.deviceId, _serviceUuid, _rxUuid, bytes, BleOutputProperty.withResponse);
      } catch (_) {
        await UniversalBle.writeValue(_deviceAlvo!.deviceId, _serviceUuid, _rxUuid, bytes, BleOutputProperty.withoutResponse);
      }
    }
  }

  void _mostrarFeedback(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text(
          "GERENCIADOR DE EQUIPAMENTOS",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.deepOrangeAccent, fontSize: 13),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF141414),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_isConectado) ...[
              const SizedBox(height: 30),
              const Center(
                child: Icon(Icons.bluetooth_searching, size: 60, color: Colors.deepOrangeAccent),
              ),
              const SizedBox(height: 16),
              const Text(
                "CONSOLE DESCONECTADO",
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 8),
              const Text(
                "Por favor, selecione seu console de movimento abaixo.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 24),

              if (dispositivosPareados.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        "DISPOSITIVOS ENCONTRADOS",
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<BleDevice>(
                          isExpanded: true,
                          value: dispositivoSelecionado ?? dispositivosPareados.first,
                          dropdownColor: const Color(0xFF141414),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          items: dispositivosPareados.map((BleDevice value) {
                            return DropdownMenuItem<BleDevice>(
                              value: value,
                              child: Row(
                                children: [
                                  const Icon(Icons.bluetooth, color: Colors.deepOrangeAccent, size: 18),
                                  const SizedBox(width: 10),
                                  Text(value.name ?? "Sem nome"),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (novoDispositivo) {
                            setState(() {
                              dispositivoSelecionado = novoDispositivo;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrangeAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.bluetooth_connected),
                  label: const Text("CONECTAR", style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () {
                    if (dispositivoSelecionado != null) {
                      _conectarAoDispositivo(dispositivoSelecionado!);
                    } else if (dispositivosPareados.isNotEmpty) {
                      _conectarAoDispositivo(dispositivosPareados.first);
                    }
                  },
                ),
              ],
            ] else ...[
              if (aparelhosRDMDescobertos.isEmpty) ...[
                const SizedBox(height: 80),
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: Colors.deepOrangeAccent),
                      SizedBox(height: 20),
                      Text(
                        "Varrendo barramento RDM...",
                        style: TextStyle(color: Colors.deepOrangeAccent, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "DISPOSITIVOS DETECTADOS",
                      style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          aparelhosRDMDescobertos.clear();
                        });
                        _enviarComando("VARREDURA_RDM", "1");
                      },
                      icon: const Icon(Icons.sync, color: Colors.deepOrangeAccent, size: 16),
                      label: const Text("RE-ESCANEAR", style: TextStyle(color: Colors.deepOrangeAccent, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: aparelhosRDMDescobertos.length,
                  itemBuilder: (context, index) {
                    final dev = aparelhosRDMDescobertos[index];
                    return Card(
                      color: const Color(0xFF141414),
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.white10),
                      ),
                      child: ListTile(
                        onTap: () => _abrirPainelDoEquipamento(dev),
                        leading: const CircleAvatar(
                          backgroundColor: Colors.deepOrangeAccent,
                          foregroundColor: Colors.black,
                          child: Icon(Icons.settings_input_composite),
                        ),
                        title: Text(
                          dev['nome'],
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        subtitle: Text(
                          "ID: ${dev['uid']} | DMX CH: ${dev['dmx']}",
                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.deepOrangeAccent, size: 16),
                      ),
                    );
                  },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}