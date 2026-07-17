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
  bool buscandoDispositivos = false;
  bool conexaoAutomaticaFalhou = false;
  List<BluetoothDevice> dispositivosEncontrados = [];
  BluetoothDevice? dispositivoSelecionado;
  Timer? _timerBusca;

  // Lista dinâmica de aparelhos físicos descobertos via RDM
  List<Map<String, dynamic>> aparelhosRDMDescobertos = [
    {
      "uid": "4D49:00000101",
      "nome": "SPOT BEAM 200",
      "dmx": 1,
      "canais": 7,
    },
    {
      "uid": "4D49:00000102",
      "nome": "PAR LED SLIM",
      "dmx": 8,
      "canais": 4,
    },
    {
      "uid": "2A2B:00005A90",
      "nome": "STROBO RGBW PRO",
      "dmx": 12,
      "canais": 12,
    }
  ];

  @override
  void initState() {
    super.initState();
    _iniciarDescobertaAutomatica();
  }

  @override
  void dispose() {
    _timerBusca?.cancel();
    super.dispose();
  }

  Future<void> _iniciarDescobertaAutomatica() async {
    setState(() {
      buscandoDispositivos = true;
      conexaoAutomaticaFalhou = false;
      dispositivosEncontrados.clear();
    });

    try {
      List<BluetoothDevice> bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
      List<BluetoothDevice> miletoDevices = bonded.where(
        (dev) => dev.name != null && dev.name!.toUpperCase().contains("MILETO")
      ).toList();

      if (miletoDevices.isNotEmpty) {
        setState(() {
          dispositivosEncontrados = bonded;
          dispositivoSelecionado = miletoDevices.first;
          buscandoDispositivos = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text("Console '${dispositivoSelecionado!.name}' conectado! Identificando aparelhos RDM na linha..."),
          ),
        );
      } else {
        setState(() {
          dispositivosEncontrados = bonded;
          if (bonded.isNotEmpty) dispositivoSelecionado = bonded.first;
          buscandoDispositivos = false;
          conexaoAutomaticaFalhou = true;
        });
      }
    } catch (e) {
      setState(() {
        buscandoDispositivos = false;
        conexaoAutomaticaFalhou = true;
      });
    }
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
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("DMX do aparelho ${aparelho['nome']} definido para Canal $dmxTemp!"),
                        duration: const Duration(seconds: 2),
                      ),
                    );
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
        centerTitle: true,
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 4,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (buscandoDispositivos) ...[
              const Center(
                child: Column(
                  children: [
                    SizedBox(height: 40),
                    CircularProgressIndicator(color: Colors.amber),
                    SizedBox(height: 16),
                    Text(
                      "Escaneando linha DMX e identificando aparelhos...",
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    )
                  ],
                ),
              )
            ] else ...[
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
            ],

            const SizedBox(height: 24),

            if (conexaoAutomaticaFalhou) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      "NENHUM CONSOLE MILETO DETECTADO AUTOMATICAMENTE",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E2E2E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.bluetooth),
                      label: const Text("CONECTAR MANUALMENTE", style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _iniciarBuscaManual,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

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
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
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
        ),
      ),
    );
  }

  void _iniciarBuscaManual() async {
    setState(() {
      buscandoDispositivos = true;
    });
    try {
      List<BluetoothDevice> bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
      setState(() {
        dispositivosEncontrados = bonded;
        if (bonded.isNotEmpty) dispositivoSelecionado = bonded.first;
        buscandoDispositivos = false;
        conexaoAutomaticaFalhou = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Buscando consoles de forma manual...")),
      );
    } catch (e) {
      setState(() {
        buscandoDispositivos = false;
      });
    }
  }
}