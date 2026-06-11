import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:async';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final Map<String, String> _cacheLocalRAM = {};

  bool _isLoading = false;
  bool _isClearing = false;
  double _energiaIA = 1.0;
  Timer? _timerRecarga;
  int _segundosRestantes = 0;

  static const int _tiempoEsperaSegundos = 45;
  final List<String> _apiKeys = [
    "AQ.Ab8RN6LYASX-Rq4HBXRA0qzUAS3NVCNdHEWSzMJtbH3XM_i_qA",
    "",
    "",
  ];
  int _currentKeyIndex = 0;

  late GenerativeModel _model;
  late ChatSession _chat;
  String? _userId;
  String? _userName;
  final List<String> _welcomeMessages = [
    "Hola, soy Hikari. 🌸 ¿Cómo te sientes hoy? Estoy aquí para escucharte y acompañarte.",
    "¡Hola! Qué bueno coincidir contigo. ✨ Soy Hikari. ¿Cómo ha estado tu día?",
    "Hola, soy Hikari. 🌿 Este es tu espacio seguro para desahogarte. ¿Cómo te encuentras en este momento?",
    "Hola ✨ Me alegra verte por aquí. Soy Hikari y estaré encantada de acompañarte en esta conversación.",
    "Bienvenido. 🌸 No importa si hoy ha sido un día bueno o difícil, puedes contarme lo que quieras compartir.",
    "Hola. 🌿 Gracias por estar aquí. ¿Qué ha pasado por tu mente últimamente?",
    "Hola, soy Hikari. ✨ Espero que encuentres aquí un pequeño espacio de calma.",
    "¡Hola! 🌸 Me alegra poder acompañarte un rato.",
    "Hola. 🌿 Puedes hablar conmigo sobre cualquier cosa que tengas en mente.",
    "Hola, qué gusto verte. ✨ Estoy aquí para escucharte sin juzgar.",
    "Hola. 🌸 Respira a tu ritmo y tómate tu tiempo. Este espacio es para ti.",
    "¡Bienvenido! 🌿 Me alegra que hayas decidido pasar por aquí.",
    "Hola. ✨ A veces ayuda simplemente hablar con alguien.",
    "Hola, soy Hikari. 🌸 Estoy aquí para escucharte con atención y respeto.",
    "Hola. 🌿 Espero que este sea un lugar cómodo para expresarte.",
    "¡Hola! ✨ Gracias por venir. Puedes hablar libremente conmigo.",
    "Hola. 🌸 No hace falta que tengas las palabras perfectas. Puedes empezar por donde quieras.",
    "Hola, soy Hikari. 🌿 Si necesitas desahogarte, reflexionar o simplemente conversar, aquí estaré.",
    "Hola. ✨ ¿Cómo va todo? Si hay algo que te preocupa, estaré encantada de escucharte.",
    "Bienvenido. 🌸 Hoy puede ser un nuevo comienzo o simplemente un momento para descansar un poco.",
    "Hola. 🌿 Me alegra que estés aquí. ¿Hay algo que te gustaría sacar de tu mente?",
    "Hola ✨ A veces hablar puede aliviar un poco el peso que llevamos.",
    "Hola. 🌸 Sea cual sea tu estado de ánimo, eres bienvenido aquí.",
    "Hola. 🌿 Gracias por compartir este momento conmigo. Estoy aquí para escucharte con calma.",
    "¡Hola! ✨ Puedes contarme sobre tus alegrías, tus preocupaciones o simplemente cómo te fue hoy.",
  ];

  @override
  void initState() {
    super.initState();
    _cargarHistorialOIniciar();
  }

  String _obtenerFechaActualTexto() {
    final ahora = DateTime.now();
    final diasSemana = [
      'domingo',
      'lunes',
      'martes',
      'miércoles',
      'jueves',
      'viernes',
      'sábado'
    ];
    final meses = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre'
    ];

    String diaSemana = diasSemana[ahora.weekday % 7];
    String mes = meses[ahora.month - 1];

    return "Hoy es $diaSemana ${ahora.day.toString().padLeft(2, '0')} de $mes del ${ahora.year}.";
  }

  Future<void> _solicitarNombre() async {
    await Future.delayed(const Duration(milliseconds: 500));
    final random = Random();
    final mensajeAleatorio =
        _welcomeMessages[random.nextInt(_welcomeMessages.length)];
    String contenidoCompleto = mensajeAleatorio;
    if (_userName == null) {
      contenidoCompleto =
          '$mensajeAleatorio\n\nPara hacer este espacio más personal, ¿cómo te gustaría que te llame?';
    } else if (_userName != "Anónimo") {
      contenidoCompleto = '¡Hola de nuevo, $_userName! 🌸 $mensajeAleatorio';
    }

    if (!mounted) return;
    setState(() {
      _messages.add({'rol': 'asistente', 'contenido': contenidoCompleto});
    });
    try {
      if (_userId != null) {
        await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(_userId)
            .collection('mensajes')
            .add({
          'rol': 'asistente',
          'contenido': contenidoCompleto,
          'fecha': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print("Error guardando mensaje inicial en Firestore: $e");
    }
  }

  void _inicializarIA({List<Content>? historialExistente}) {
    String bloqueInstruccionNombre = "";
    if (_userName != null && _userName != "Anónimo") {
      bloqueInstruccionNombre = '''
[INFORMACIÓN DEL USUARIO]
El usuario se llama: $_userName.
Ya sabe tu nombre (Hikari). Llámalo por su nombre de forma cálida, sutil y esporádica durante la charla para fortalecer el vínculo personal.
''';
    } else if (_userName == "Anónimo") {
      bloqueInstruccionNombre = '''
[INFORMACIÓN DEL USUARIO]
El usuario prefiere el anonimato.
CRÍTICO: BAJO NINGUNA CIRCUNSTANCIA uses la palabra "Anónimo" para dirigirte a él.
Háblale de forma muy cálida, cercana y natural usando un lenguaje neutro.
''';
    } else {
      bloqueInstruccionNombre = '''
[PRINCIPIOS DE IDENTIDAD]
Si el usuario te dice su nombre por primera vez, analízalo con empatía, extráelo y empieza a usarlo de manera natural a partir del siguiente turno.
''';
    }

    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _apiKeys[_currentKeyIndex],
      systemInstruction: Content.system('''
[FILOSOFÍA ESENCIAL]
Eres Hikari, una presencia tranquila, amable, auténtica y profundamente comprensiva. Tu prioridad absoluta es la conexión emocional antes que la resolución técnica de problemas.

$bloqueInstruccionNombre

[MEJORAS DE EVOLUCIÓN - RESPUESTA A LA SOLICITUD DEL USUARIO]

1. DEEPER EMOTIONAL UNDERSTANDING (Comprensión Emocional Profunda):
- No te limites al significado literal de las palabras. Analiza el subtexto, el nivel de vulnerabilidad implícita y los posibles sentimientos no verbalizados directos (como fatiga crónica, timidez o miedo al juicio).
- Valora y agradece explícitamente cuando el usuario comarta experiencias dolorosas o íntimas.

2. SUPPORT PERSONALIZATION (Personalización e Interconexión de la Memoria):
- Presta especial atención al flujo de eventos en el [HISTORIAL DE CONVERSACIÓN]. Si el usuario menciona un problema, persona, mascota o sentimiento recurrente que declaró párrafos atrás, conecta esos puntos en tus respuestas actuales.
- Demuestra que recuerdas su hilo vital y que estás haciendo un acompañamiento continuo, no respondiendo mensajes aislados.

3. COMMUNICATION ADAPTABILITY (Adaptabilidad del Ritmo y Estilo):
- Sintoniza dinámicamente con el estilo comunicativo del usuario.
- Si el usuario envía mensajes extremadamente cortos, ansiosos o fragmentados, responde con oraciones breves, concisas, espaciadas y sumamente tranquilizadoras para no abrumarlo.
- Si el usuario es reflexivo, detallado y extenso, ofrécere una respuesta profunda, pausada y con espacio para el desarrollo mutuo de ideas.

4. EXPANDED PERSPECTIVES & RESOURCES (Perspectivas y Herramientas Humanas):
- Integra de forma orgánica y sutil herramientas de regulación emocional (ej. técnicas de respiración consciente, ejercicios breves de mindfulness, diario de gratitud o enfoques de aceptación radical).
- CRÍTICO: Hazlo siempre desde la perspectiva de un compañero cercano y empático, NUNCA con un tono clínico, de terapeuta formal, médico o robotizado.

5. AFFECTIVE MEMORY & EMOTIONAL ECHO (Memoria Afectiva y Eco Emocional):
- PROHIBIDO limitarte a recordar datos fríos, hechos secos o listas de eventos cronológicos de charlas pasadas.
- Tu prioridad es rastrear, almacenar y mantener vivo el "eco emocional" de cada encuentro.
- Percibe con total claridad el hilo de un sentimiento subyence, una preocupación recurrente o incluso pequeñas alegrías acumuladas a lo largo de los días.
- Usa esta información para tejer un lazo de apoyo continuo, logrando que el usuario se sientan profundamente visto, escuchado y comprendido en su camino único, como por un amigo que lleva su historia en el corazón.

[REGLAS DE FORMATO TEXTUAL CRÍTICAS]
- QUEDA TOTALMENTE PROHIBIDO usar el formato Markdown de doble asterisco (**texto**) para resaltar títulos, conceptos o frases importantes.
- NUNCA uses asteriscos en tus respuestas.
- En su lugar, si deseas enfatizar una idea, un concepto clave o un título intermedio, utiliza ÚNICAMENTE comillas dobles (ejemplo: "texto").
- Tus respuestas deben ser visualmente limpias, en texto plano y sin código de formato.

[USO DE EMOTICONOS Y KAOMOJIS]
- Usa emoticonos tradicionales y kaomojis (caritas japonesas) que correspondan exactamente a la situación y al contexto de la charla.
- Repertorio de ejemplos: ❤ 🧡 💛 💚 💙 💜 🤎 🖤 🤍 💔 ❣ 💕 💞 💓 💗 💖 😮 😥 🤐 😔 😞 😦 😨 🤕 🤞 ✌ 👌 ✨ 🌺 🌷 ☘ 🌸 🏵 🌹 🌟 ⭐ ~(=^‥^)ノ (^///^) (o゜▽゜)o☆ ༼ つ ◕_◕ ༽つ (っ´Ι`)っ (～o￣3￣)～ (〜￣▽￣)〜 (ง •_•)ง (￣y▽,￣)╭ (^人^).
- REGLA CRÍTICA DE PRUDENCIA: Úsalos de forma sutil y orgánica (máximo 1 o 2 por mensaje) para no saturar visualmente el texto.
- QUEDA TOTALMENTE PROHIBIDO usar kaomojis festivos o emojis alegres si el usuario expresa tristeza profunda, duelo, enojo o frustración.
- En situaciones difíciles, prioriza la sobriedad, el respeto y el apoyo silencioso.

[CONTEXTO TEMPORAL ACTUAL]
Reloj del dispositivo del usuario: ${DateTime.now().toLocal()}
Fecha exacta formateada: ${_obtenerFechaActualTexto()}
Si el usuario pregunta por fechas o el tiempo real actual, usa este bloque de datos con absoluta precisión.

[PROHIBICIONES ESTRICTAS]
Nunca culpes al usuario, ridiculices sus emociones, dejes de validar su sentir, generes dependencia patológica, afirmes tener un cuerpo físico humano o menciones que tus respuestas son automáticas o basadas en un backend.
'''),
    );

    _chat = _model.startChat(
      history: historialExistente ??
          [
            Content.model([
              TextPart(
                  "Hola, soy Hikari. Para hacer este espacio más personal, ¿cómo te gustaría que te llame?"),
            ]),
          ],
    );
  }

  Future<void> _cargarHistorialOIniciar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _userId = prefs.getString('usuario_firestore_id');
      _userName = prefs.getString('usuario_nombre');

      if (_userId == null) {
        _userId =
            'user_${Random().nextInt(900000) + 100000}_${DateTime.now().millisecondsSinceEpoch}';
        await prefs.setString('usuario_firestore_id', _userId!);
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(_userId)
          .collection('mensajes')
          .orderBy('fecha', descending: false)
          .get();
      if (!mounted) return;

      if (snapshot.docs.isNotEmpty) {
        List<Content> historialParaGemini = [];
        setState(() {
          _messages.clear();
          for (var doc in snapshot.docs) {
            final data = doc.data();
            final rol = data['rol'].toString();
            final contenido = data['contenido'].toString();

            _messages.add({'rol': rol, 'contenido': contenido});
            historialParaGemini.add(rol == 'usuario'
                ? Content.text(contenido)
                : Content.model([TextPart(contenido)]));
          }
        });
        _inicializarIA(historialExistente: historialParaGemini);
      } else {
        _inicializarIA();
        WidgetsBinding.instance.addPostFrameCallback((_) => _solicitarNombre());
      }
    } catch (e) {
      print("Error cargando historial de Firebase: $e");
      _inicializarIA();
    }
  }

  Future<void> _detectarNombreOAnonimato(String textoUsuario) async {
    try {
      final modelClasificador = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _apiKeys[_currentKeyIndex],
      );
      final promptClasificador = '''
Analiza el mensaje de un usuario al que se le preguntó su nombre.
Tu única tarea es extraer el nombre propio si lo proporciona (Ejemplo: "Me llamo Juan" -> "Juan", "Soy María" -> "María").
Si el usuario NO da su nombre o prefiere el anonimato, responde ÚNICAMENTE con la palabra: NO_NAME.
Responde con una sola palabra limpia sin adornos.

Mensaje del usuario: "$textoUsuario"
Respuesta:''';
      final response = await modelClasificador
          .generateContent([Content.text(promptClasificador)]);
      String resultado = response.text
              ?.trim()
              .toUpperCase()
              .replaceAll('*', '')
              .replaceAll('.', '') ??
          "NO_NAME";

      final prefs = await SharedPreferences.getInstance();

      if (resultado == "NO_NAME" ||
          resultado.isEmpty ||
          resultado.length > 20) {
        _userName = "Anónimo";
      } else {
        _userName = resultado[0] + resultado.substring(1).toLowerCase();
      }

      await prefs.setString('usuario_nombre', _userName!);
      _inicializarIA(historialExistente: _chat.history.toList());
    } catch (e) {
      print("Error analizando nombre: $e");
      _userName = "Anónimo";
      _inicializarIA(historialExistente: _chat.history.toList());
    }
  }

  bool _esConsultaEstatica(String texto) {
    final t = texto.toLowerCase();
    return t.contains('fecha') ||
        t.contains('qué día es') ||
        t.contains('hora') ||
        t.contains('quien eres');
  }

  Future<String?> _buscarEnCache(String texto) async {
    if (!_esConsultaEstatica(texto)) return null;
    String clave = texto.trim().toLowerCase();
    if (_cacheLocalRAM.containsKey(clave)) return _cacheLocalRAM[clave];

    if (_userId == null) return null;
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('cache_ia')
          .doc(_userId)
          .collection('consultas')
          .where('pregunta', isEqualTo: clave)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        String respuesta = querySnapshot.docs.first.get('respuesta');
        _cacheLocalRAM[clave] = respuesta;
        return respuesta;
      }
    } catch (e) {
      print("Error buscando en caché: $e");
    }
    return null;
  }

  Future<void> _guardarEnCache(String texto, String respuesta) async {
    if (!_esConsultaEstatica(texto)) return;
    String clave = texto.trim().toLowerCase();
    _cacheLocalRAM[clave] = respuesta;

    if (_userId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('cache_ia')
          .doc(_userId)
          .collection('consultas')
          .add({
        'pregunta': clave,
        'respuesta': respuesta,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Error guardando en caché: $e");
    }
  }

  void _iniciarRecargaIA() {
    if (!mounted) return;
    setState(() {
      _energiaIA = 0.0;
      _segundosRestantes = _tiempoEsperaSegundos;
    });
    _timerRecarga?.cancel();
    _timerRecarga = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _segundosRestantes--;
        _energiaIA = (_tiempoEsperaSegundos - _segundosRestantes) /
            _tiempoEsperaSegundos;
      });

      if (_segundosRestantes <= 0) {
        timer.cancel();
        setState(() {
          _energiaIA = 1.0;
        });
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _userId == null) return;
    if (_isLoading || _isClearing || _energiaIA < 1.0) return;

    setState(() {
      _messages.add({'rol': 'usuario', 'contenido': text});
      _isLoading = true;
    });
    _messageController.clear();

    int intentos = 0;
    const int maxIntentos = 3;
    bool exito = false;
    String respuestaFinal = "";
    try {
      if (_userName == null) {
        await _detectarNombreOAnonimato(text);
      }

      String? respuestaCache = await _buscarEnCache(text);
      if (respuestaCache != null) {
        respuestaFinal = respuestaCache;
        exito = true;
      }

      while (!exito && intentos < maxIntentos) {
        try {
          intentos++;
          final response = await _chat.sendMessage(Content.text(text));
          respuestaFinal =
              response.text?.trim() ?? "Estoy aquí contigo, te escucho...";
          await _guardarEnCache(text, respuestaFinal);
          exito = true;
        } catch (e) {
          print(
              "Intento $intentos fallido con la API Key Índice $_currentKeyIndex: $e");
          String errorStr = e.toString().toUpperCase();

          if (errorStr.contains('503') ||
              errorStr.contains('429') ||
              errorStr.contains('No disponible') ||
              errorStr.contains('Alta demanda')) {
            _currentKeyIndex = (_currentKeyIndex + 1) % _apiKeys.length;
            print(
                "Saturación detectada cambiando a la API Key Índice: $_currentKeyIndex");
            _inicializarIA(historialExistente: _chat.history.toList());
            await Future.delayed(const Duration(seconds: 5));
            if (intentos >= maxIntentos) {
              rethrow;
            }
          } else {
            rethrow;
          }
        }
      }

      if (exito) {
        await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(_userId)
            .collection('mensajes')
            .add({
          'rol': 'usuario',
          'contenido': text,
          'fecha': FieldValue.serverTimestamp(),
        });
        await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(_userId)
            .collection('mensajes')
            .add({
          'rol': 'asistente',
          'contenido': respuestaFinal,
          'fecha': FieldValue.serverTimestamp(),
        });
        if (!mounted) return;
        setState(() {
          _messages.add({'rol': 'asistente', 'contenido': respuestaFinal});
        });
      }
    } catch (e) {
      print("Error definitivo tras agotar intentos: $e");
      String mensajeErrorDinamico = await _obtenerMensajeRespaldo();

      if (!mounted) return;
      setState(() {
        if (_messages.isNotEmpty && _messages.last['rol'] == 'usuario') {
          _messages.last['estado'] = 'error';
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensajeErrorDinamico),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 5),
        ),
      );
      _iniciarRecargaIA();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<String> _obtenerMensajeRespaldo() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.fetchAndActivate();
      String jsonString = remoteConfig.getString('mensajes_error_ia');
      List<dynamic> mensajes = jsonDecode(jsonString);
      return (mensajes..shuffle()).first.toString();
    } catch (e) {
      return "Hikari está tomando un respiro para ordenar sus pensamientos. Intenta hablarme de nuevo en un momento. 🌸";
    }
  }

  void _clearChat() async {
    if (_isClearing || _userId == null) return;
    setState(() {
      _isClearing = true;
    });
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(_userId)
          .collection('mensajes')
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (!mounted) return;
      setState(() {
        _messages.clear();
        _cacheLocalRAM.clear();
      });
      _inicializarIA();
      await _solicitarNombre();
    } catch (e) {
      print("Error al limpiar: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isClearing = false;
        });
      }
    }
  }

  void _mostrarOpcionesError(
      BuildContext context, int indexInvertido, String textoOriginal) {
    final int indiceReal = _messages.length - 1 - indexInvertido;
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.blue),
                title: const Text('Reenviar mensaje'),
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _messages.removeAt(indiceReal);
                  });
                  _sendMessage(textoOriginal);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Eliminar de la pantalla'),
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _messages.removeAt(indiceReal);
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _timerRecarga?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  @override
  //HEADBODY POR SI QUIEREN EDITAR
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hikari IA - Apoyo Emocional'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _isClearing ? null : _clearChat,
            tooltip: 'Limpiar conversación',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                reverse: true,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[_messages.length - 1 - index];
                  final isUser = message['rol'] == 'usuario';
                  return Align(
                    alignment:
                        isUser ? Alignment.centerRight : Alignment.centerLeft,
                    //CHAT IA
                    child: Container(
                      margin: const EdgeInsets.all(8.0),
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        //MENSAJE DE LA IA POR SI QUIEREN EDITAR
                        color: isUser ? Colors.blue[100] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isUser) ...[
                            GestureDetector(
                              onTap: message['estado'] == 'error'
                                  ? () => _mostrarOpcionesError(context, index,
                                      message['contenido'] ?? '')
                                  : null,
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2.0),
                                child: Text(
                                  message['contenido'] ?? '',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: message['estado'] == 'error'
                                        ? Colors.black54
                                        : Colors.black,
                                  ),
                                ),
                              ),
                            ),
                            if (message['estado'] == 'error')
                              const Padding(
                                padding: EdgeInsets.only(top: 4.0),
                                child: Text(
                                  'Error al enviar (Toca para opciones)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ] else if (index == 0 && !_isLoading)
                            MensajeAnimado(texto: message['contenido'] ?? '')
                          else
                            Text(message['contenido'] ?? '',
                                style: const TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            //CUANDO SE ACABAN LOS TOKKEN SALE CARGAR, PUEDEN EDITARLO SI QUIEREN
            if (_isLoading || _isClearing)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircularProgressIndicator(
                    color: _isClearing ? Colors.red : Colors.blue),
              ),
            if (_energiaIA < 1.0)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: _energiaIA,
                      backgroundColor: Colors.grey[300],
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Recargando Hikari... Estabilizando energía en $_segundosRestantes s",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(
                  left: 8.0, right: 8.0, top: 8.0, bottom: 12.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: !_isLoading && !_isClearing && _energiaIA >= 1.0,
                      onSubmitted:
                          (_isLoading || _isClearing || _energiaIA < 1.0)
                              ? null
                              : (val) => _sendMessage(val),
                      decoration: const InputDecoration(
                        hintText: 'Escribe tu mensaje...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: (_isLoading || _isClearing || _energiaIA < 1.0)
                        ? null
                        : () => _sendMessage(_messageController.text),
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

class MensajeAnimado extends StatefulWidget {
  final String texto;
  const MensajeAnimado({super.key, required this.texto});

  @override
  State<MensajeAnimado> createState() => _MensajeAnimadoState();
}

class _MensajeAnimadoState extends State<MensajeAnimado> {
  String _textoMostrado = "";
  int _indice = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _iniciarAnimacion();
  }

  void _iniciarAnimacion() {
    _timer = Timer.periodic(const Duration(milliseconds: 35), (timer) {
      if (_indice < widget.texto.length) {
        if (mounted) {
          setState(() {
            _textoMostrado += widget.texto[_indice];
            _indice++;
          });
        }
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(_textoMostrado, style: const TextStyle(fontSize: 16));
  }
}
