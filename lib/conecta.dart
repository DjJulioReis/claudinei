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
  String? perfilSelecionado = "Pista Geral (Padrão)";
  bool buscandoDispositivos = false;
  bool conexaoAutomaticaFalhou = false;
  List<BluetoothDevice> dispositivosEncontrados = [];
  BluetoothDevice? dispositivoSelecionado;
  Timer? _timerBusca;

  final List<Map<String, dynamic>> perfisDisponiveis = [
    {
      "nome": "Pista Geral (Padrão)",
      "desc": "Controle de grids e efeitos sequenciais de pista de LED",
      "icone": Icons.grid_on,
    },
    {
      "nome": "Refletores Wash (Par LED)",
      "desc": "Configuração otimizada para canais de cores e strobo",
      "icone": Icons.lightbulb,
    },
    {
      "nome": "Painel de Efeitos (Pista Z)",
      "desc": "Mapeamento personalizado para fitas digitais e efeitos rápidos",
      "icone": Icons.flash_on,
    },
    {
      "nome": "Moving Heads (Spot X)",
      "desc": "Controle dedicado para canais de PAN, TILT e gobo",
      "icone": Icons.settings_input_hdmi,
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

  // --- BUSCA AUTOMÁTICA DE CONSOLE MILETO NO BOOT ---
  Future<void> _iniciarDescobertaAutomatica() async {
    setState(() {
      buscandoDispositivos = true;
      conexaoAutomaticaFalhou = false;
      dispositivosEncontrados.clear();
    });

    try {
      // 1. Pede a lista de dispositivos já pareados com o celular
      List<BluetoothDevice> bonded = await FlutterBluetoothSerial.instance.getBondedDevices();

      // 2. Procura se algum deles tem o nome "MILETO"
      List<BluetoothDevice> miletoDevices = bonded.where(
        (dev) => dev.name != null && dev.name!.toUpperCase().contains("MILETO")
      ).toList();

      if (miletoDevices.isNotEmpty) {
        // Se achou automaticamente, conecta e abre
        setState(() {
          dispositivosEncontrados = bonded;
          dispositivoSelecionado = miletoDevices.first;
          buscandoDispositivos = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text("Console '${dispositivoSelecionado!.name}' encontrado automaticamente! Conectando..."),
          ),
        );

        // Aguarda 1.5s para dar uma experiência visual fluida e inicia o HomeScreen
        _timerBusca = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            );
          }
        });
      } else {
        // Se não achou nenhum com o padrão MILETO nos pareados, tenta carregar todos para escolha manual
        setState(() {
          dispositivosEncontrados = bonded;
          if (bonded.isNotEmpty) dispositivoSelecionado = bonded.first;
          buscandoDispositivos = false;
          conexaoAutomaticaFalhou = true; // Exibe o botão de conexão manual
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text("Nenhum console MILETO detectado automaticamente. Use a conexão manual."),
          ),
        );
      }
    } catch (e) {
      setState(() {
        buscandoDispositivos = false;
        conexaoAutomaticaFalhou = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text(
          "CONEXÃO MILETO",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.amber),
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
            Center(
              child: buscandoDispositivos
                  ? const Column(
                      children: [
                        SizedBox(height: 20),
                        CircularProgressIndicator(color: Colors.amber),
                        SizedBox(height: 16),
                        Text(
                          "Buscando consoles MILETO automaticamente...",
                          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                        )
                      ],
                    )
                  : const Icon(Icons.bluetooth_searching, size: 60, color: Colors.amber),
            ),
            const SizedBox(height: 12),
            const Text(
              "O sistema tenta detectar o seu console MILETO automaticamente. Caso ele não seja encontrado, você pode selecioná-lo de forma manual abaixo.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),

            // --- EXIBIÇÃO DE ACORDO COM O STATUS DA BUSCA ---
            if (conexaoAutomaticaFalhou) ...[
              // --- CONTAINER SELEÇÃO DE APARELHO MANUAL ---
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "CONEXÃO MANUAL BLUETOOTH",
                          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.amber, size: 18),
                          onPressed: _iniciarBuscaManual,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    dispositivosEncontrados.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              "Nenhum dispositivo Bluetooth pareado no celular! Por favor, ative o Bluetooth e pareie a mesa nas configurações do Android/iOS.",
                              style: TextStyle(color: Colors.redAccent, fontSize: 12),
                            ),
                          )
                        : DropdownButtonHideUnderline(
                            child: DropdownButton<BluetoothDevice>(
                              isExpanded: true,
                              value: dispositivoSelecionado,
                              dropdownColor: const Color(0xFF1E1E1E),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              items: dispositivosEncontrados.map((BluetoothDevice value) {
                                return DropdownMenuItem<BluetoothDevice>(
                                  value: value,
                                  child: Row(
                                    children: [
                                      const Icon(Icons.bluetooth, color: Colors.greenAccent, size: 18),
                                      const SizedBox(width: 10),
                                      Text(value.name ?? "Dispositivo sem nome"),
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
              const SizedBox(height: 16),
            ],

            // --- CONTAINER SELEÇÃO DE PERFIL ---
            const Text(
              "SELECIONE O PERFIL DE OPERAÇÃO",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1),
            ),
            const SizedBox(height: 10),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: perfisDisponiveis.length,
              itemBuilder: (context, index) {
                final perfil = perfisDisponiveis[index];
                final bool isSelected = perfilSelecionado == perfil['nome'];

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        perfilSelecionado = perfil['nome'];
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.amber.withOpacity(0.08) : const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? Colors.amber : Colors.white10,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(perfil['icone'] as IconData, color: isSelected ? Colors.amber : Colors.grey, size: 28),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  perfil['nome'] as String,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: isSelected ? Colors.amber : Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  perfil['desc'] as String,
                                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle, color: Colors.amber, size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // --- BOTÃO CONFIRMAR E ABRIR CONSOLE ---
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
                  Icon(Icons.power_settings_new, fontWeight: FontWeight.bold),
                  SizedBox(width: 8),
                  Text(
                    "CONECTAR E ABRIR CONSOLE",
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
      });
    } catch (e) {
      setState(() {
        buscandoDispositivos = false;
      });
    }
  }
}