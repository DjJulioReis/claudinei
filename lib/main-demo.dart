import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyAppDemo());
}

class MyAppDemo extends StatelessWidget {
  const MyAppDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Controle MILETO - DEMO',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.amber,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.amber,
          secondary: Colors.amberAccent,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreenDemo(),
    );
  }
}

// --- TELA DE ABERTURA DEMO ---
class SplashScreenDemo extends StatefulWidget {
  const SplashScreenDemo({super.key});

  @override
  State<SplashScreenDemo> createState() => _SplashScreenDemoState();
}

class _SplashScreenDemoState extends State<SplashScreenDemo> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 3), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ConectaPageDemo()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/mileto_logo.png',
              width: 180,
              height: 180,
              errorBuilder: (context, error, stackTrace) {
                return const Text(
                  "MILETO",
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                    letterSpacing: 4.0,
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                color: Colors.amber,
                backgroundColor: Colors.white10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- TELA DE CONEXÃO E DESCOBERTA RDM AUTOMÁTICA DEMO ---
class ConectaPageDemo extends StatefulWidget {
  const ConectaPageDemo({super.key});

  @override
  State<ConectaPageDemo> createState() => _ConectaPageDemoState();
}

class _ConectaPageDemoState extends State<ConectaPageDemo> {
  bool _isCarregando = false;
  bool _isConectado = false;
  bool _autenticado = false;

  List<String> dispositivosPareados = ["MILETO_C3 (Disponível)", "CONSERTO_PULSO", "MESA_AUX_LIGHT"];
  String? dispositivoSelecionado = "MILETO_C3 (Disponível)";

  List<Map<String, dynamic>> aparelhosRDMDescobertos = [];

  void _iniciarConexaoAutomatica() {
    setState(() {
      _isCarregando = true;
    });

    // Simula tempo de busca e conexão bluetooth real de 2 segundos
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isConectado = true;
          _autenticado = true;
          _isCarregando = false;
          // Popula com dados simulados incríveis para o Claudinei ver tudo em tempo real
          aparelhosRDMDescobertos = [
            {
              "uid": "4D49:00000101",
              "nome": "SPOT BEAM 200 (Mileto)",
              "dmx": 1,
              "canais": 7,
            },
            {
              "uid": "4D49:00000102",
              "nome": "PAR LED SLIM (Mileto)",
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
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text("Mesa 'MILETO_C3' Conectada! Descoberta RDM de aparelhos concluída com sucesso."),
          ),
        );
      }
    });
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
                        content: Text("DMX do aparelho ${aparelho['nome']} definido para Canal $dmxTemp via RDM!"),
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
            if (!_isConectado) ...[
              const SizedBox(height: 30),
              Center(
                child: _isCarregando
                    ? const CircularProgressIndicator(color: Colors.amber)
                    : const Icon(Icons.bluetooth_disabled, size: 60, color: Colors.redAccent),
              ),
              const SizedBox(height: 16),
              const Text(
                "CONSOLE DESCONECTADO (DEMO)",
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 8),
              const Text(
                "Use a conexão demonstrativa simulada para apresentar as funções de forma totalmente autônoma e sem necessidade de placa.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 24),

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
                      "DISPOSITIVOS BLUETOOTH SIMULADOS",
                      style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: dispositivoSelecionado,
                        dropdownColor: const Color(0xFF1E1E1E),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        items: dispositivosPareados.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Row(
                              children: [
                                const Icon(Icons.bluetooth, color: Colors.amber, size: 18),
                                const SizedBox(width: 10),
                                Text(value),
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
                label: const Text("INICIAR CONEXÃO DEMO", style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _iniciarConexaoAutomatica,
              ),
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
                      builder: (_) => const HomeScreenDemo(),
                    ),
                  );
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.dashboard_customize, fontWeight: FontWeight.bold),
                    SizedBox(width: 8),
                    Text(
                      "ABRIR CONSOLE DEMO",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- CONSOLE PRINCIPAL MOCKED / SIMULADO ---
class HomeScreenDemo extends StatefulWidget {
  const HomeScreenDemo({super.key});

  @override
  State<HomeScreenDemo> createState() => _HomeScreenDemoState();
}

class _HomeScreenDemoState extends State<HomeScreenDemo> {
  int modoAtual = 0;
  double velocidad = 50;
  double brilhoGeral = 80;
  int enderecoDMX = 1;
  bool modoDMX = false;

  bool _painelLiberado = false;
  final String _senhaCorreta = "1234";
  final TextEditingController _senhaController = TextEditingController();

  List<String> modosLista = ["MANUAL", "FADE", "STROBO", "SEQUENC", "FIXO"];

  int tamanhoGrade = 4;
  bool executandoEfeito = true;
  List<double> niveisReaisCanais = [80.0, 40.0, 90.0, 10.0];

  List<double> brilhoCanaisManuais = [80.0, 70.0, 90.0, 50.0];
  Timer? _timerBlink;

  @override
  void initState() {
    super.initState();
    _iniciarSimulacaoEfeitos();
  }

  @override
  void dispose() {
    _timerBlink?.cancel();
    _senhaController.dispose();
    super.dispose();
  }

  // Blinda canais simulando oscilações e efeitos visuais reais para o Claudinei ver brilhando na tela
  void _iniciarSimulacaoEfeitos() {
    _timerBlink = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (mounted) {
        setState(() {
          if (modoAtual == 1) { // Fade
            niveisReaisCanais[0] = (niveisReaisCanais[0] + 5) % 100;
            niveisReaisCanais[1] = (100 - niveisReaisCanais[0]);
            niveisReaisCanais[2] = niveisReaisCanais[1];
            niveisReaisCanais[3] = niveisReaisCanais[0];
          } else if (modoAtual == 2) { // Strobo
            bool aceso = (timer.tick % 2 == 0);
            niveisReaisCanais = List.generate(4, (_) => aceso ? brilhoGeral : 0.0);
          } else if (modoAtual == 3) { // Sequencial
            int ativo = timer.tick % 4;
            niveisReaisCanais = List.generate(4, (i) => i == ativo ? brilhoGeral : 0.0);
          } else if (modoAtual == 4) { // Fixo
            niveisReaisCanais = List.generate(4, (_) => brilhoGeral);
          } else { // Manual
            niveisReaisCanais = List.from(brilhoCanaisManuais);
          }
        });
      }
    });
  }

  void _mostrarFeedback(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _verificarSenha() {
    if (_senhaController.text == _senhaCorreta) {
      setState(() {
        _painelLiberado = true;
      });
      _senhaController.clear();
      _mostrarFeedback("🔓 Acesso liberado (Modo de Demonstração)!");
    } else {
      _senhaController.clear();
      _mostrarFeedback("❌ Senha incorreta! Digite 1234.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/mileto_logo.png',
          height: 35,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Text(
                "MILETO DEMO",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 18, letterSpacing: 1.5)
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth_connected, color: Colors.greenAccent),
            onPressed: () {
              _mostrarFeedback("Você está rodando no modo demonstrativo off-line.");
            },
          )
        ],
        centerTitle: true,
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
      ),
      body: SafeArea(
        child: !_painelLiberado
            ? _buildTelaDeSenha()
            : SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: mediaQuery.padding.bottom + 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    "⚡ CONEXÃO DEMOSTRATIVA ATIVA ⚡",
                    style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              Card(
                color: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          modoDMX ? "MODO DMX ATIVO" : "MODO MANUAL / RF",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: modoDMX ? Colors.cyan : Colors.amber),
                        ),
                      ),
                      Switch(
                        value: modoDMX,
                        activeColor: Colors.cyan,
                        inactiveThumbColor: Colors.amber,
                        onChanged: (value) {
                          setState(() {
                            modoDMX = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: modoDMX ? _buildPainelDMX() : _buildPainelManuais(),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.save),
                label: const Text("SALVAR CONFIGURAÇÕES (SIMULADO)", style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  _mostrarFeedback("💾 Configurações gravadas com sucesso na NVS simulada!");
                },
              ),
              const SizedBox(height: 24),
              const Center(child: Text("SIMULADOR DE MÓDULOS REAIS (PISO/GRADE)", style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 2))),
              const SizedBox(height: 10),
              _buildSimuladorPistaLed(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTelaDeSenha() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: Colors.amber),
            const SizedBox(height: 16),
            const Text(
              "SISTEMA RESTRITO (DEMO)",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            const Text(
              "Digite 1234 para testar o console de demonstração.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _senhaController,
              obscureText: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 4,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
              decoration: InputDecoration(
                counterText: "",
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                hintText: "••••",
                hintStyle: const TextStyle(color: Colors.white24),
              ),
              onSubmitted: (_) => _verificarSenha(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _verificarSenha,
                child: const Text("ENTRAR", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPainelDMX() {
    return Card(
      key: const ValueKey(1),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Text("CANAL DMX SELECIONADO", style: TextStyle(color: Colors.grey)),
            Text("$enderecoDMX", style: const TextStyle(fontSize: 50, fontWeight: FontWeight.bold, color: Colors.cyan)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Colors.cyan.withOpacity(0.1)),
                  icon: const Icon(Icons.remove, color: Colors.cyan),
                  onPressed: () {
                    setState(() { if (enderecoDMX > 1) enderecoDMX--; });
                  },
                ),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Colors.cyan.withOpacity(0.1)),
                  icon: const Icon(Icons.add, color: Colors.cyan),
                  onPressed: () {
                    setState(() { if (enderecoDMX < 512) enderecoDMX++; });
                  },
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildAnaliseGeral() {
    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(Icons.analytics_outlined, size: 18, color: Colors.amber),
                SizedBox(width: 8),
                Text("ANÁLISE DE SAÍDAS EM TEMPO REAL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(4, (index) {
                return Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        Container(
                          width: 25,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          width: 25,
                          height: (niveisReaisCanais[index] / 100.0) * 80,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.amber.shade900,
                                Colors.amber,
                                Colors.amberAccent,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(color: Colors.amber.withOpacity(0.3), blurRadius: 8, spreadRadius: 1),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text("CH${index + 1}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    Text("${niveisReaisCanais[index].toInt()}%", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber)),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPainelManuais() {
    bool isEfeitoManualAtivo = modoAtual == 0;

    return Column(
      key: const ValueKey(2),
      children: [
        _buildAnaliseGeral(),
        const SizedBox(height: 8),
        Card(
          color: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("EFEITOS SELECIONÁVEIS", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: modosLista.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 2.2),
                  itemBuilder: (context, index) {
                    final bool sel = modoAtual == index;
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: sel ? Colors.amber : const Color(0xFF2E2E2E),
                        foregroundColor: sel ? Colors.black : Colors.white,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        setState(() => modoAtual = index);
                      },
                      child: Text(modosLista[index], style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        if (isEfeitoManualAtivo) ...[
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("CONTROLE MANUAL INDEPENDENTE", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 16),
                  ...List.generate(4, (index) {
                    return _buildSliderRow("CANAL ${index + 1}", brilhoCanaisManuais[index], (val) {
                      setState(() => brilhoCanaisManuais[index] = val);
                    });
                  }),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        _buildSliderCard(
          modoAtual == 0 ? "VELOCIDADE DA OSCILAÇÃO" : "VELOCIDADE (STROBO / EFEITOS)",
          velocidad,
          (val) => setState(() => velocidad = val)
        ),
        const SizedBox(height: 8),
        _buildSliderCard("BRILHO GERAL", brilhoGeral, (val) => setState(() => brilhoGeral = val)),
      ],
    );
  }

  Widget _buildSliderRow(String label, double valor, Function(double) onCh) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              Text("${valor.toInt()}%", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: valor,
              min: 0,
              max: 100,
              divisions: 100,
              activeColor: Colors.amber,
              inactiveColor: Colors.white10,
              onChanged: onCh,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderCard(String label, double valor, Function(double) onCh) {
    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                Text("${valor.toInt()}%", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
              ],
            ),
            Slider(
              value: valor,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: onCh,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimuladorPistaLed() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("QUANTIDADE DE PLACAS:", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
              DropdownButton<int>(
                value: tamanhoGrade,
                dropdownColor: const Color(0xFF1E1E1E),
                style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                underline: Container(height: 2, color: Colors.amber),
                items: [3, 4, 5, 6].map((int value) {
                  return DropdownMenuItem<int>(
                    value: value,
                    child: Text(" Placas (${value}x$value)"),
                  );
                }).toList(),
                onChanged: (novoTamanho) {
                  if (novoTamanho != null) {
                    setState(() {
                      tamanhoGrade = novoTamanho;
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: 200,
            height: 200,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: CustomPaint(
              size: Size.infinite,
              painter: LedGridPainterDemo(
                gridSize: tamanhoGrade,
                niveisCanais: niveisReaisCanais,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.withOpacity(0.15),
                    foregroundColor: Colors.amber,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.flash_on, size: 18),
                  label: const Text("TESTAR DISPARO", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    _mostrarFeedback("Efeito sequencial simulado com sucesso!");
                    setState(() {
                      modoAtual = 3;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.15),
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.power_settings_new, size: 18),
                  label: const Text("APAGAR PISTA", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    _mostrarFeedback("Pista apagada na simulação!");
                    setState(() {
                      niveisReaisCanais = [0.0, 0.0, 0.0, 0.0];
                    });
                  },
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}

class LedGridPainterDemo extends CustomPainter {
  final int gridSize;
  final List<double> niveisCanais;

  LedGridPainterDemo({
    required this.gridSize,
    required this.niveisCanais,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final int totalPlacas = gridSize * gridSize;
    final double spacing = 6.0;

    final double cellWidth = (size.width - (spacing * (gridSize - 1))) / gridSize;
    final double cellHeight = (size.height - (spacing * (gridSize - 1))) / gridSize;

    final Color corApagado = Colors.grey.shade900;
    const Color corBase = Colors.amber;

    for (int i = 0; i < totalPlacas; i++) {
      int row = i ~/ gridSize;
      int col = i % gridSize;

      int canalIdx = i % 4;
      double nivel = niveisCanais[canalIdx] / 100.0;

      double x = col * (cellWidth + spacing);
      double y = row * (cellHeight + spacing);

      final Rect rectPlaca = Rect.fromLTWH(x, y, cellWidth, cellHeight);

      Color corDaPlaca = nivel > 0
          ? corBase.withOpacity(nivel.clamp(0.1, 1.0))
          : corApagado;

      if (nivel > 0) {
        final Paint glowPaint = Paint()
          ..color = corBase.withOpacity(nivel * 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawRect(rectPlaca.inflate(2), glowPaint);
      }

      final Paint ledPaint = Paint()
        ..color = corDaPlaca
        ..style = PaintingStyle.fill;

      canvas.drawRRect(RRect.fromRectAndRadius(rectPlaca, const Radius.circular(4)), ledPaint);
    }
  }

  @override
  bool shouldRepaint(covariant LedGridPainterDemo oldDelegate) {
    return oldDelegate.gridSize != gridSize ||
        oldDelegate.niveisCanais != niveisCanais;
  }
}