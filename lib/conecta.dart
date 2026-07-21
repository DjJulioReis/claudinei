import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'main.dart';

class ConectaPage extends StatefulWidget {
  final BluetoothDevice? activeDevice;
  final BluetoothConnection? activeConnection;
  const ConectaPage({super.key, this.activeDevice, this.activeConnection});

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

  // Lista de pareados do celular para fallback de conexão manual
  List<BluetoothDevice> dispositivosPareados = [];
  BluetoothDevice? dispositivoSelecionado;

  // Lista dinâmica que conterá APENAS os aparelhos RDM físicos encontrados ou já salvos
  List<Map<String, dynamic>> aparelhosRDMDescobertos = [];

  @override
  void initState() {
    super.initState();
    if (widget.activeDevice != null && widget.activeConnection != null) {
      _connection = widget.activeConnection;
      _isConectado = true;
      _autenticado = true;
      _isCarregando = false;
      dispositivoSelecionado = widget.activeDevice;
      _configurarListenerBLE();
      // Dispara a varredura RDM imediatamente
      Future.delayed(const Duration(milliseconds: 500), () {
        _enviarComando("VARREDURA_RDM", "1");
        _mostrarFeedback("Atualizando barramento RDM...");
      });
    } else {
      _carregarPareadosETentarConexaoAutomatica();
    }
  }

  // --- CARREGAR DISPOSITIVOS PAREADOS DO CELULAR ---
  Future<void> _carregarPareadosETentarConexaoAutomatica() async {
    setState(() {
      _isCarregando = true;
    });

    try {
      List<BluetoothDevice> bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
      setState(() {
        dispositivosPareados = bonded;
      });

      // Tenta achar se já existe um dispositivo pareado com o nome "MILETO"
      BluetoothDevice? autoDevice;
      for (var dev in bonded) {
        if (dev.name != null && dev.name!.toUpperCase().contains(_nomeDispositivoAlvo)) {
          autoDevice = dev;
          break;
        }
      }

      if (autoDevice != null) {
        _conectarAoDispositivo(autoDevice);
      } else {
        setState(() {
          _isCarregando = false;
          if (bonded.isNotEmpty) {
            dispositivoSelecionado = bonded.first;
          }
        });
        _mostrarFeedback("Console 'MILETO' não achado automaticamente. Selecione-o manualmente abaixo.");
      }
    } catch (e) {
      setState(() {
        _isCarregando = false;
      });
      _mostrarFeedback("Erro ao carregar dispositivos do celular.");
    }
  }

  // --- FUNÇÃO CENTRAL DE CONEXÃO AO DISPOSITIVO BLUETOOTH ---
  Future<void> _conectarAoDispositivo(BluetoothDevice device) async {
    setState(() {
      _isCarregando = true;
      _autenticado = false;
      aparelhosRDMDescobertos.clear();
    });

    try {
      BluetoothConnection connection = await BluetoothConnection.toAddress(device.address);
      setState(() {
        _connection = connection;
        _isConectado = true;
        _isCarregando = false;
        dispositivoSelecionado = device;
      });

      _configurarListenerBLE();

    } catch (e) {
      _mostrarFeedback("Falha de conexão com o console.");
      setState(() {
        _isConectado = false;
        _isCarregando = false;
        _autenticado = false;
        aparelhosRDMDescobertos.clear();
      });
    }
  }

  void _configurarListenerBLE() {
    if (_connection == null) return;
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
          _mostrarFeedback("Autenticação válida! Escaneando barramento DMX...");
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
          _mostrarFeedback("Varredura concluída! ${aparelhosRDMDescobertos.length} aparelhos encontrados.");
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
                    // Envia o comando DMX atualizado para a placa via RDM
                    _enviarComando("SET_DMX", "${aparelho['uid']},$dmxTemp");
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
                  onPressed: _carregarPareadosETentarConexaoAutomatica,
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
                "Ligue e pareie o Bluetooth do console MILETO nas configurações do seu celular.",
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
                        "DISPOSITIVOS BLUETOOTH ENCONTRADOS",
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<BluetoothDevice>(
                          isExpanded: true,
                          value: dispositivoSelecionado ?? dispositivosPareados.first,
                          dropdownColor: const Color(0xFF1E1E1E),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          items: dispositivosPareados.map((BluetoothDevice value) {
                            return DropdownMenuItem<BluetoothDevice>(
                              value: value,
                              child: Row(
                                children: [
                                  const Icon(Icons.bluetooth, color: Colors.amber, size: 18),
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
                        "Nenhum aparelho encontrado ainda.",
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                )
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.devices_other, color: Colors.amber, size: 20),
                        SizedBox(width: 10),
                        Text(
                          "APARELHOS RDM ENCONTRADOS",
                          style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          aparelhosRDMDescobertos.clear();
                        });
                        _enviarComando("VARREDURA_RDM", "1");
                        _mostrarFeedback("Solicitando nova varredura física...");
                      },
                      icon: const Icon(Icons.sync, color: Colors.amber, size: 16),
                      label: const Text(
                        "RE-ESCANEAR",
                        style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
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
                        builder: (_) => HomeScreen(connection: _connection, deviceAlvo: dispositivoSelecionado),
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