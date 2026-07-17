import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'main.dart';

class ConectaPage extends StatefulWidget {
  const ConectaPage({super.key});

  @override
  State<ConectaPage> createState() => _ConectaPageState();
}

class _ConectaPageState extends State<ConectaPage> {
  bool _isCarregando = false;
  bool _isConectado = false;
  BluetoothConnection? _connection;
  final String _nomeDispositivoAlvo = "MILETO";
  String _bufferDadosIncompletos = "";

  // Autenticação Handshake
  bool _autenticado = false;

  // Lista dinâmica de aparelhos RDM reais descobertos pelo ESP32-C3
  List<Map<String, dynamic>> aparelhosRDMDescobertos = [];

  @override
  void initState() {
    super.initState();
    _inicializarEConectarBluetooth();
  }

  @override
  void dispose() {
    // Atenção: Não fechamos a conexão aqui se formos passá-la para o HomeScreen!
    super.dispose();
  }

  // --- CONEXÃO BLUETOOTH E PARSER RDM REAL ---
  Future<void> _inicializarEConectarBluetooth() async {
    setState(() {
      _isCarregando = true;
      _autenticado = false;
      aparelhosRDMDescobertos.clear();
    });

    try {
      List<BluetoothDevice> bondedDevices = await FlutterBluetoothSerial.instance.getBondedDevices();
      BluetoothDevice? dispositivoMileto;

      for (var device in bondedDevices) {
        if (device.name != null && device.name!.toUpperCase().contains(_nomeDispositivoAlvo)) {
          dispositivoMileto = device;
          break;
        }
      }

      if (dispositivoMileto != null) {
        BluetoothConnection connection = await BluetoothConnection.toAddress(dispositivoMileto.address);

        setState(() {
          _connection = connection;
          _isConectado = true;
          _isCarregando = false;
        });

        _connection!.input?.listen((data) {
          _bufferDadosIncompletos += utf8.decode(data);

          while (_bufferDadosIncompletos.contains('\n')) {
            int posicaoQuebra = _bufferDadosIncompletos.indexOf('\n');
            String linhaComando = _bufferDadosIncompletos.substring(0, posicaoQuebra).trim();
            _bufferDadosIncompletos = _bufferDadosIncompletos.substring(posicaoQuebra + 1);

            if (linhaComando.isEmpty) continue;

            // Tratamento do Handshake de Autenticação
            if (linhaComando.startsWith("AUTH_CHALLENGE:")) {
              String desafioStr = linhaComando.replaceAll("AUTH_CHALLENGE:", "");
              int? desafio = int.tryParse(desafioStr);
              if (desafio != null) {
                int resposta = (desafio * 2) + 7;
                _enviarComando("AUTH_RESPONSE", "$resposta");
              }
            }
            else if (linhaComando.contains("MILETO_AUTH:VALID")) {
              setState(() {
                _autenticado = true;
              });
              _mostrarFeedback("Conectado e Autenticado! Escaneando linha DMX...");
              // Solicita varredura RDM
              _enviarComando("VARREDURA_RDM", "1");
            }
            else if (linhaComando == "RDM_START") {
              setState(() {
                aparelhosRDMDescobertos.clear();
              });
            }
            // Recebimento de equipamento RDM: RDM_DEV:fabricante,ID,DMX_CH,canais,nome
            else if (linhaComando.startsWith("RDM_DEV:")) {
              String dados = linhaComando.replaceAll("RDM_DEV:", "");
              List<String> partes = dados.split(",");
              if (partes.length >= 5) {
                setState(() {
                  aparelhosRDMDescobertos.add({
                    "uid": "${partes[0].toUpperCase()}:${partes[1].toUpperCase()}",
                    "nome": partes[4].replaceAll("_", " "),
                    "dmx": int.tryParse(partes[2]) ?? 1,
                    "canais": int.tryParse(partes[3]) ?? 1,
                  });
                });
              }
            }
            else if (linhaComando == "RDM_END") {
              _mostrarFeedback("Mapeamento RDM concluído! ${aparelhosRDMDescobertos.length} aparelhos encontrados.");
            }
          }
        }).onDone(() {
          setState(() {
            _isConectado = false;
            _connection = null;
            _autenticado = false;
            aparelhosRDMDescobertos.clear();
          });
          _mostrarFeedback("O console foi desconectado.");
        });

      } else {
        _mostrarFeedback("Console 'MILETO' não pareado no Bluetooth!");
        setState(() => _isCarregando = false);
      }
    } catch (e) {
      _mostrarFeedback("Falha na conexão física com a mesa.");
      setState(() {
        _isConectado = false;
        _isCarregando = false;
        _autenticado = false;
        aparelhosRDMDescobertos.clear();
      });
    }
  }

  void _enviarComando(String comando, String valor) async {
    String bufferCompleto = "$comando:$valor\n";
    if (_connection != null && _connection!.isConnected) {
      _connection!.output.add(utf8.encode(bufferCompleto));
      await _connection!.output.allSent;
    }
  }

  void _mostrarFeedback(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _abrirConfiguracaoDMX(Map<String, dynamic> aparelho) {
    int dmxTemp = aparelho['dmx'];
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              title: Text(
                "CONFIGURAR DMX: ${aparelho['nome']}",
                style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "UID: ${aparelho['uid']}",
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  const Text("Endereço DMX Inicial:", style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle, color: Colors.amber, size: 32),
                        onPressed: () {
                          if (dmxTemp > 1) {
                            setDialogState(() => dmxTemp--);
                          }
                        },
                      ),
                      const SizedBox(width: 16),
                      Text(
                        "$dmxTemp",
                        style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.amber, size: 32),
                        onPressed: () {
                          if (dmxTemp < 512) {
                            setDialogState(() => dmxTemp++);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("CANCELAR", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                  onPressed: () {
                    setState(() {
                      aparelho['dmx'] = dmxTemp;
                    });
                    // Envia comando RDM real de setar endereço para a placa
                    _enviarComando("SET_DMX", "$dmxTemp");
                    Navigator.pop(context);
                    _mostrarFeedback("DMX do aparelho ${aparelho['nome']} definido para Canal $dmxTemp!");
                  },
                  child: const Text("SALVAR REMOTAMENTE (RDM)", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text(
          "VARREDURA RDM AUTOMÁTICA",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.amber, fontSize: 16),
        ),
        actions: [
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
                  onPressed: _inicializarEConectarBluetooth,
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
              const SizedBox(height: 60),
              const Center(
                child: Icon(Icons.bluetooth_disabled, size: 80, color: Colors.redAccent),
              ),
              const SizedBox(height: 20),
              const Text(
                "DESCONECTADO DO CONSOLE",
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                "Certifique-se de que a mesa MILETO está ligada e pareada no Bluetooth do celular. Em seguida, clique no ícone superior direito para conectar.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.bluetooth),
                label: const Text("CONECTAR MANUALMENTE", style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _inicializarEConectarBluetooth,
              ),
            ] else ...[
              if (aparelhosRDMDescobertos.isEmpty) ...[
                const SizedBox(height: 80),
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: Colors.amber),
                      SizedBox(height: 20),
                      Text(
                        "Varrendo linha DMX física...",
                        style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text(
                        "Buscando equipamentos compatíveis com RDM",
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                )
              ] else ...[
                const Row(
                  children: [
                    Icon(Icons.devices_other, color: Colors.amber, size: 20),
                    SizedBox(width: 10),
                    Text(
                      "APARELHOS RDM ENCONTRADOS NA LINHA",
                      style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1),
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
                      color: const Color(0xFF1E1E1E),
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.white10),
                      ),
                      child: ListTile(
                        onTap: () => _abrirConfiguracaoDMX(dev),
                        leading: const CircleAvatar(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                          child: Icon(Icons.lightbulb_outline),
                        ),
                        title: Text(
                          dev['nome'],
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        subtitle: Text(
                          "ID (UID): ${dev['uid']} | Canais: ${dev['canais']}",
                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber),
                          ),
                          child: Text(
                            "DMX CH ${dev['dmx']}",
                            style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 30),

                // --- BOTÃO PROSSEGUIR PARA O CONSOLE ---
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                  ),
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => HomeScreen(connection: _connection),
                      ),
                    );
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.dashboard_customize, fontWeight: FontWeight.bold),
                      SizedBox(width: 8),
                      Text(
                        "ABRIR CONSOLE PRINCIPAL",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}