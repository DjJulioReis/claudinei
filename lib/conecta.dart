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
  List<BluetoothDevice> dispositivosEncontrados = [];
  BluetoothDevice? dispositivoSelecionado;

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
    _carregarDispositivosPareados();
  }

  Future<void> _carregarDispositivosPareados() async {
    setState(() {
      buscandoDispositivos = true;
    });

    try {
      List<BluetoothDevice> bonded = await FlutterBluetoothSerial.instance.getBondedDevices();
      setState(() {
        dispositivosEncontrados = bonded;
        if (bonded.isNotEmpty) {
          // Tenta pré-selecionar o primeiro dispositivo ou um que chame MILETO
          dispositivoSelecionado = bonded.firstWhere(
            (dev) => dev.name != null && dev.name!.contains("MILETO"),
            orElse: () => bonded.first,
          );
        }
        buscandoDispositivos = false;
      });
    } catch (e) {
      setState(() {
        buscandoDispositivos = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Erro ao carregar dispositivos pareados.")),
      );
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
            const Center(
              child: Icon(Icons.bluetooth_searching, size: 60, color: Colors.amber),
            ),
            const SizedBox(height: 12),
            const Text(
              "Selecione um console e escolha o perfil de funcionamento antes de abrir a mesa de controle principal.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 24),

            // --- CONTAINER SELEÇÃO DE APARELHO ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "DISPOSITIVO ALVO (PAREADOS)",
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                      buscandoDispositivos
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber))
                          : IconButton(
                              icon: const Icon(Icons.refresh, color: Colors.amber, size: 18),
                              onPressed: _carregarDispositivosPareados,
                            ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  dispositivosEncontrados.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            "Nenhum console pareado no sistema! Por favor, pareie o dispositivo 'MILETO' nas configurações de Bluetooth do seu celular.",
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
}