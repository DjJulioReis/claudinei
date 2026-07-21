import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Controle MILETO',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.amber,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.amber,
          secondary: Colors.amberAccent,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

// --- TELA DE ABERTURA (SPLASH SCREEN COM LOGO) ---
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 3), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
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

class HomeScreen extends StatefulWidget {
  final BluetoothConnection? connection;
  final BluetoothDevice? deviceAlvo;
  const HomeScreen({super.key, this.connection, this.deviceAlvo});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _abaAtiva = 0; // 0 = Console Paris, 1 = Mesa DMX 16 Canais
  List<double> fadersDMX16 = List.generate(16, (_) => 0.0);

  int modoAtual = 0;
  double velocidad = 100;
  double brilhoGeral = 100;
  int enderecoDMX = 1;
  bool modoDMX = false;

  BluetoothConnection? _connection;
  bool _isConectado = false;
  bool _isCarregando = false;
  final String _nomeDispositivoAlvo = "MILETO";

  // --- SISTEMA DE SENHA ---
  bool _painelLiberado = false;
  final String _senhaCorreta = "1234";
  final TextEditingController _senhaController = TextEditingController();

  List<String> modosLista = [];
  String _bufferDadosIncompletos = "";

  // --- CONTROLE TELEMÉTRICO DA PISTA (DIRETO DO ESP32) ---
  int tamanhoGrade = 4;
  bool executandoEfeito = false;
  List<double> niveisReaisCanais = [0.0, 0.0, 0.0, 0.0];

  // --- VALORES DOS CANAIS MANUAIS ---
  List<double> brilhoCanaisManuais = [100.0, 100.0, 100.0, 100.0];

  int get totalPlacas => tamanhoGrade * tamanhoGrade;
  int get totalCanais => 4;

  @override
  void initState() {
    super.initState();
    if (widget.connection != null) {
      _connection = widget.connection;
      _isConectado = _connection!.isConnected;
      _configurarListenerBluetooth();
    } else {
      _inicializarEConectarBluetooth();
    }
  }

  void _configurarListenerBluetooth() {
    _connection!.input?.listen((data) {
      _bufferDadosIncompletos += utf8.decode(data);

      while (_bufferDadosIncompletos.contains('\n')) {
        int posicaoQuebra = _bufferDadosIncompletos.indexOf('\n');
        String linhaComando = _bufferDadosIncompletos.substring(0, posicaoQuebra).trim();
        _bufferDadosIncompletos = _bufferDadosIncompletos.substring(posicaoQuebra + 1);

        if (linhaComando.isEmpty) continue;

        if (linhaComando.startsWith("CH_LEVELS:")) {
          String dados = linhaComando.replaceAll("CH_LEVELS:", "");
          List<String> niveis = dados.split(",");
          if (niveis.length >= 4) {
            setState(() {
              niveisReaisCanais = List.generate(4, (i) => double.tryParse(niveis[i]) ?? 0.0);
              executandoEfeito = niveisReaisCanais.any((v) => v > 0);
            });
          }
        }
        else if (linhaComando.contains("CONNECTED_OK")) {
          setState(() => _isConectado = true);
          _mostrarFeedback("MILETO Conectada!");
          enviarComando("GET_CAPABILITIES", "1");
        }
        else if (linhaComando.startsWith("CAPS:")) {
          String listaEfeitos = linhaComando.replaceAll("CAPS:", "");
          setState(() {
            modosLista = listaEfeitos.split(",");
          });
        }
        else if (linhaComando.startsWith("CHAVE_MODO:")) {
          String modoVindoDaPlaca = linhaComando.replaceAll("CHAVE_MODO:", "");
          setState(() {
            modoDMX = (modoVindoDaPlaca == "DMX");
          });
          _mostrarFeedback(modoDMX ? "Modo Alterado: Mesa DMX" : "Modo Alterado: Controle Bluetooth");
        }
        else if (linhaComando.contains("[MEMORIA]") || linhaComando.contains("GRAVAR:OK")) {
          _mostrarFeedback("💾 Configurações gravadas com sucesso!");
        }
      }
    }).onDone(() {
      setState(() {
        _isConectado = false;
        _connection = null;
        modosLista.clear();
        _bufferDadosIncompletos = "";
        _painelLiberado = false;
        _inicializarPistaLeds();
      });
      _mostrarFeedback("A placa foi desconectada.");
    });

    enviarComando("GET_CAPABILITIES", "1");
    setState(() {
      _painelLiberado = true; // Já vem autenticado do conecta.dart
    });
  }

  void _inicializarPistaLeds() {
    setState(() {
      executandoEfeito = false;
      niveisReaisCanais = [0.0, 0.0, 0.0, 0.0];
      brilhoCanaisManuais = [100.0, 100.0, 100.0, 100.0];
    });
  }

  @override
  void dispose() {
    _connection?.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _inicializarEConectarBluetooth() async {
    setState(() {
      _isCarregando = true;
      modosLista.clear();
      _painelLiberado = false;
    });

    try {
      List<BluetoothDevice> bondedDevices = await FlutterBluetoothSerial.instance.getBondedDevices();
      BluetoothDevice? dispositivoMileto;

      for (var device in bondedDevices) {
        if (device.name == _nomeDispositivoAlvo) {
          dispositivoMileto = device;
          break;
        }
      }

      if (dispositivoMileto != null) {
        BluetoothConnection connection = await BluetoothConnection.toAddress(dispositivoMileto.address);

        setState(() {
          _connection = connection;
          _isCarregando = false;
        });

        _connection!.input?.listen((data) {
          _bufferDadosIncompletos += utf8.decode(data);

          while (_bufferDadosIncompletos.contains('\n')) {
            int posicaoQuebra = _bufferDadosIncompletos.indexOf('\n');
            String linhaComando = _bufferDadosIncompletos.substring(0, posicaoQuebra).trim();
            _bufferDadosIncompletos = _bufferDadosIncompletos.substring(posicaoQuebra + 1);

            if (linhaComando.isEmpty) continue;

            if (linhaComando.startsWith("CH_LEVELS:")) {
              String dados = linhaComando.replaceAll("CH_LEVELS:", "");
              List<String> niveis = dados.split(",");
              if (niveis.length >= 4) {
                setState(() {
                  niveisReaisCanais = List.generate(4, (i) => double.tryParse(niveis[i]) ?? 0.0);
                  executandoEfeito = niveisReaisCanais.any((v) => v > 0);
                });
              }
            }
            else if (linhaComando.contains("CONNECTED_OK")) {
              setState(() => _isConectado = true);
              _mostrarFeedback("MILETO Conectada! Insira a senha de acesso.");
              enviarComando("GET_CAPABILITIES", "1");
            }
            else if (linhaComando.startsWith("CAPS:")) {
              String listaEfeitos = linhaComando.replaceAll("CAPS:", "");
              setState(() {
                modosLista = listaEfeitos.split(",");
              });
            }
            else if (linhaComando.startsWith("CHAVE_MODO:")) {
              String modoVindoDaPlaca = linhaComando.replaceAll("CHAVE_MODO:", "");
              setState(() {
                modoDMX = (modoVindoDaPlaca == "DMX");
              });
              _mostrarFeedback(modoDMX ? "Modo Alterado: Mesa DMX" : "Modo Alterado: Controle Bluetooth");
            }
            else if (linhaComando.contains("[MEMORIA]") || linhaComando.contains("GRAVAR:OK")) {
              _mostrarFeedback("💾 Configurações gravadas com sucesso!");
            }
          }
        }).onDone(() {
          setState(() {
            _isConectado = false;
            _connection = null;
            modosLista.clear();
            _bufferDadosIncompletos = "";
            _painelLiberado = false;
            _inicializarPistaLeds();
          });
          _mostrarFeedback("A placa foi desconectada.");
        });

        enviarComando("PING", "1");

      } else {
        _mostrarFeedback("Dispositivo 'MILETO' não pareado!");
        setState(() => _isCarregando = false);
      }
    } catch (e) {
      _mostrarFeedback("Falha na conexão física do rádio.");
      setState(() {
        _isConectado = false;
        _isCarregando = false;
        modosLista.clear();
        _bufferDadosIncompletos = "";
        _painelLiberado = false;
      });
    }
  }

  void enviarComando(String comando, String valor) async {
    String bufferCompleto = "$comando:$valor\n";
    if (_connection != null && _connection!.isConnected) {
      _connection!.output.add(utf8.encode(bufferCompleto));
      await _connection!.output.allSent;
    }
  }

  void _solicitarTesteDisparo() {
    enviarComando("EFEITO_PISTA", "START");
  }

  void _solicitarApagarPista() {
    enviarComando("EFEITO_PISTA", "CLEAR");
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
      _mostrarFeedback("🔓 Acesso liberado com sucesso!");
    } else {
      _senhaController.clear();
      _mostrarFeedback("❌ Senha incorreta! Tente novamente.");
    }
  }

  Widget _buildMesaDMX16() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.tune, color: Colors.cyan),
                          SizedBox(width: 8),
                          Text(
                            "MESA DMX MANUAL - 16 CANAIS",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            fadersDMX16 = List.generate(16, (_) => 0.0);
                          });
                          for (int i = 1; i <= 16; i++) {
                            enviarComando("SET_CH$i", "0");
                          }
                          _mostrarFeedback("Mesa DMX resetada!");
                        },
                        icon: const Icon(Icons.clear_all, color: Colors.redAccent, size: 18),
                        label: const Text("Zerar Tudo", style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 340,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: 16,
                      itemBuilder: (context, index) {
                        final int canal = index + 1;
                        return Container(
                          width: 75,
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF121212),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            children: [
                              Text(
                                "CH $canal",
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyan, fontSize: 12),
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                                    ),
                                    child: Slider(
                                      value: fadersDMX16[index],
                                      min: 0,
                                      max: 255,
                                      divisions: 255,
                                      activeColor: Colors.cyan,
                                      inactiveColor: Colors.white10,
                                      onChanged: (val) {
                                        setState(() {
                                          fadersDMX16[index] = val;
                                        });
                                      },
                                      onChangeEnd: (val) {
                                        enviarComando("SET_CH$canal", "${val.round()}");
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "${fadersDMX16[index].round()}",
                                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
                "MILETO",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 18, letterSpacing: 1.5)
            );
          },
        ),
        actions: [
          if (_isConectado)
            IconButton(
              icon: const Icon(Icons.sync, color: Colors.amberAccent),
              tooltip: "Re-escanear Barramento RDM",
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => ConectaPage(
                      activeConnection: _connection,
                      activeDevice: widget.deviceAlvo,
                    ),
                  ),
                );
              },
            ),
          _isCarregando
              ? const Padding(
            padding: EdgeInsets.all(16.0),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
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
        elevation: 0,
      ),
      body: SafeArea(
        child: !_isConectado
            ? const Center(child: Text("DESCONECTADO\n(TOQUE NO ÍCONE SUPERIOR PARA CONECTAR)", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
            : !_painelLiberado
            ? _buildTelaDeSenha()
            : _abaAtiva == 1 ? _buildMesaDMX16() : SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: mediaQuery.padding.bottom + 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    "⚡ LINK ATIVO - RESPONDENDO ⚡",
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
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
                            enviarComando("CHAVE_MODO", modoDMX ? "DMX" : "RF");
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
                label: const Text("GRAVAR NA MEMÓRIA", style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  enviarComando("GRAVAR", "EEPROM");
                },
              ),
              const SizedBox(height: 24),
              const Center(child: Text("SIMULADOR DE MÓDULOS REAIS", style: TextStyle(color: Colors.grey, fontSize: 11, letterSpacing: 2))),
              const SizedBox(height: 10),
              _buildSimuladorPistaLed(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _isConectado && _painelLiberado ? BottomNavigationBar(
        currentIndex: _abaAtiva,
        selectedItemColor: Colors.amber,
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color(0xFF1E1E1E),
        onTap: (index) {
          setState(() {
            _abaAtiva = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: "Pista Paris",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.tune),
            label: "Mesa 16 CHs",
          ),
        ],
      ) : null,
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
              "SISTEMA RESTRITO",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
            const SizedBox(height: 8),
            const Text(
              "Digite o PIN de segurança para liberar o console.",
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
            const Text("CANAL DMX", style: TextStyle(color: Colors.grey)),
            Text("$enderecoDMX", style: const TextStyle(fontSize: 50, fontWeight: FontWeight.bold, color: Colors.cyan)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly, // <- Corrigido aqui!
              children: [
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Colors.cyan.withOpacity(0.1)),
                  icon: const Icon(Icons.remove, color: Colors.cyan),
                  onPressed: () {
                    setState(() { if (enderecoDMX > 1) enderecoDMX--; });
                    enviarComando("SET_DMX", "$enderecoDMX");
                  },
                ),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: Colors.cyan.withOpacity(0.1)),
                  icon: const Icon(Icons.add, color: Colors.cyan),
                  onPressed: () {
                    setState(() { if (enderecoDMX < 512) enderecoDMX++; });
                    enviarComando("SET_DMX", "$enderecoDMX");
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
                Text("ANÁLISE GERAL EM TEMPO REAL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
    bool isEfeitoManualAtivo = modosLista.isNotEmpty &&
        modoAtual < modosLista.length &&
        modosLista[modoAtual].trim().toUpperCase() == "MANUAL";

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
                const Text("EFEITOS MILETO", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                modosLista.isEmpty
                    ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20.0),
                    child: Text("Aguardando mapa de efeitos da placa...", style: TextStyle(color: Colors.white38, fontSize: 13)),
                  ),
                )
                    : GridView.builder(
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
                        enviarComando("SET_MODO", "$modoAtual");
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
                    }, "SET_CH${index + 1}");
                  }),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (!isEfeitoManualAtivo) ...[
          _buildSliderCard("VELOCIDADE (STROBO / EFEITOS)", velocidad, (val) => setState(() => velocidad = val), "SET_VEL"),
          const SizedBox(height: 8),
          _buildSliderCard("BRILHO GERAL", brilhoGeral, (val) => setState(() => brilhoGeral = val), "SET_DIM"),
        ] else ...[
          _buildSliderCard("VELOCIDADE DA OSCILAÇÃO", velocidad, (val) => setState(() => velocidad = val), "SET_VEL"),
        ],
      ],
    );
  }

  Widget _buildSliderRow(String label, double valor, Function(double) onCh, String cmd) {
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
              onChangeEnd: (v) => enviarComando(cmd, "${v.toInt()}"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderCard(String label, double valor, Function(double) onCh, String cmd) {
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
              onChangeEnd: (v) => enviarComando(cmd, "${v.toInt()}"),
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
                      _solicitarApagarPista();
                    });
                    enviarComando("SET_GRID", "${novoTamanho}x$novoTamanho");
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
              painter: LedGridPainter(
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
                  onPressed: _solicitarTesteDisparo,
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
                  onPressed: _solicitarApagarPista,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}

class LedGridPainter extends CustomPainter {
  final int gridSize;
  final List<double> niveisCanais;

  LedGridPainter({
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

      // Mapeia a placa para um dos 4 canais (distribuição em quadrantes ou alternada)
      // Aqui usamos uma lógica simples: i % 4
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
  bool shouldRepaint(covariant LedGridPainter oldDelegate) {
    return oldDelegate.gridSize != gridSize ||
        oldDelegate.niveisCanais != niveisCanais;
  }
}