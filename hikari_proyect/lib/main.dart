import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // Asegúrate de importar esto
import 'firebase_options.dart'; // Este archivo se crea con el CLI de Firebase
// IMPORTANTE: Asegúrate de mantener la ruta correcta a tu pantalla de chat
import 'screens/chat_screen.dart';

// NUEVO: Agregamos "async" porque encender Firebase toma unos milisegundos
void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Indispensable

  // Esta es la conexión que te falta:
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hikari IA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const ChatScreen(),
    );
  }
}
