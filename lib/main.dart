import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env
  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Alert to Divert',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6E2B2B)),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
        textTheme: Theme.of(context)
            .textTheme
            .apply(bodyColor: Colors.white, displayColor: Colors.white),
      ),
      home: session == null ? const LoginScreen() : const HomeScreen(),
    );
  }
}
