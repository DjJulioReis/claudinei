import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'main.dart';
import 'mileto_control_page.dart';

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

  // Lista dinâmica contendo apenas os aparelhos RDM físicos reais encontrados na hora
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
      // Dispara a varredura RDM imediatamente
      Future.delayed(const Duration(milliseconds: 500), () {
        _enviarComando("VARREDURA_RDM", "1");
        _mostrarFeedback("Atualizando barramento RDM...");
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

          print("📝 RDM Conecta recebido: $linha");

          if (linha.startsWith("AUTH_CHALLENGE:")) {
            int challenge = int.tryParse(linha.split(":")[1]) ?? 0;
            int response = (challenge * 2) + 7;
            _enviarComando("AUTH_RESPONSE", "$response");
          } else if (linha.contains("MILETO_AUTH:VALID")) {
            setState(() {
              _autenticado = true;
            });
            _mostrarFeedback("Mesa MILETO Autenticada! Varrendo linha DMX...");
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
                });
              });

              // --- REGRA DE REDIRECIONAMENTO AUTOMÁTICO DE ACORDO COM O PROTOCOLO ---
              // Se detectar que o equipamento RDM físico é um Elevador / Motor Cinético
              if (modelName.contains("ELEVADOR") || modelName.contains("KINETIC") || modelName.contains("MOTOR")) {
                _mostrarFeedback("Elevador Cinético Identificado! Abrindo Painel...");
                Future.delayed(const Duration(milliseconds: 600), () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => MiletoControlPage(deviceAlvo: _deviceAlvo),
                    ),
                  );
                });
              } else {
                // Se for Pista Paris / Outros, encaminha automaticamente para o HomeScreen
                _mostrarFeedback("Piso de LED Paris Identificado! Abrindo Console...");
                Future.delayed(const Duration(milliseconds: 600), () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => HomeScreen(deviceAlvo: _deviceAlvo),
                    ),
                  );
                });
              }
            }
          } else if (linha == "RDM_END") {
            _mostrarFeedback("Mapeamento concluído!");
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
      _mostrarFeedback("⚠️ Permissões negadas.");
      return;
    }

    try {
      await UniversalBle.startScan();

      Completer<BleDevice> c = Completer();
      UniversalBle.onScanResult = (device) {
        String name = device.name ?? 'Sem Nome';
        if (device.name != null && !dispositivosPareados.any((d) => d.deviceId == device.deviceId)) {
          setState(() {
            dispositivosPareados.add(device);
          });
        }
        if (name.toUpperCase().contains("MILETO")) {
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
      _mostrarFeedback("Mesa não encontrada automaticamente. Use a conexão manual.");
    }
  }

  Future<void> _conectarAoDispositivo(BleDevice device) async {
    setState(() {
      _isCarregando = true;
      _deviceAlvo = device;
    });

    try {
      int tent = 0;
      bool ok = false;
      while (tent < 3 && !ok) {
        tent++;
        try {
          await UniversalBle.connect(device.deviceId);
          ok = true;
        } catch (e) {
          if (tent >= 3) rethrow;
          await Future.delayed(const Duration(milliseconds: 1500));
        }
      }

      await Future.delayed(const Duration(milliseconds: 800));
      try {
        await UniversalBle.requestMtu(device.deviceId, 251);
        print("MTU configurado com sucesso para 251 bytes!");
      } catch (e) {
        print("Erro ao solicitar MTU: $e");
      }
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
      _mostrarFeedback("Falha na conexão.");
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
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text(
          _autenticado ? "CONEXÃO AUTENTICADA" : "VARREDURA RDM AUTOMÁTICA",
          style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.amber, fontSize: 14),
        ),
        actions: [
          if (_autenticado)
            const Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: Icon(Icons.verified, color: Colors.greenAccent, size: 20),
            ),
          _isCarregando
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber)),
                )
              : IconButton(
                  icon: Icon(
                    _isConectado ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    color: _isConectado ? Colors.greenAccent : Colors.redAccent,
                  ),
                  onPressed: _iniciarDescobertaAutomatica,
                )
        ],
        centerTitle: true,
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 4,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_isConectado) ...[
              const SizedBox(height: 30),
              const Center(
                child: Icon(Icons.bluetooth_disabled, size: 60, color: Colors.redAccent),
              ),
              const SizedBox(height: 16),
              const Text(
                "CONSOLE DESCONECTADO",
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 8),
              const Text(
                "Por favor, ative o Bluetooth e selecione o console MILETO abaixo.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 24),

              if (dispositivosPareados.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        "DISPOSITIVOS BLUETOOTH DETECTADOS",
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<BleDevice>(
                          isExpanded: true,
                          value: dispositivoSelecionado ?? dispositivosPareados.first,
                          dropdownColor: const Color(0xFF1E1E1E),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          items: dispositivosPareados.map((BleDevice value) {
                            String idCurto = value.deviceId.length > 5
                                ? value.deviceId.substring(value.deviceId.length - 5)
                                : value.deviceId;
                            return DropdownMenuItem<BleDevice>(
                              value: value,
                              child: Row(
                                children: [
                                  const Icon(Icons.bluetooth, color: Colors.amber, size: 18),
                                  const SizedBox(width: 10),
                                  Text("${value.name ?? "Sem nome"} (ID: ${idCurto.toUpperCase()})"),
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
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.bluetooth_connected),
                  label: const Text("CONECTAR AO SELECIONADO", style: TextStyle(fontWeight: FontWeight.bold)),
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
              const SizedBox(height: 80),
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Colors.amber),
                    SizedBox(height: 20),
                    Text(
                      "Identificando equipamento físico...",
                      style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "Lendo assinatura RDM do barramento",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              )
            ],
          ],
        ),
      ),
    );
  }
}