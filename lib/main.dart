import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() async {
  await dotenv.load(fileName: '.env');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Chat App",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ChatApp(),
    );
  }
}

class ChatApp extends StatefulWidget {
  const ChatApp({super.key});

  @override
  _ChatAppState createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> {
  final TextEditingController _controller = TextEditingController();
  final List<ChatMessage> _messages = [];
  final FlutterTts flutterTts = FlutterTts();
  final ScrollController _scrollController = ScrollController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isLoading = false;
  bool _isListening = false;
  bool _isSpeechAvailable = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _initSpeech();
  }

  void _initTts() {
    flutterTts.setLanguage("en-US");
    flutterTts.setSpeechRate(0.5);
  }

  void _initSpeech() async {
    _isSpeechAvailable = await _speech.initialize();
    setState(() {});
  }

  Future<void> _sendMessage(String message) async {
    setState(() {
      _isLoading = true;
      _messages.add(ChatMessage(text: message, isMe: true));
    });
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['OPENAI_API_KEY']}',
        },
        body: jsonEncode({
          "model": "gpt-3.5-turbo",
          "messages": [
            {"role": "user", "content": message}
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final chatGptReply = data['choices'][0]['message']['content'];
        setState(() {
          _messages.add(ChatMessage(text: chatGptReply, isMe: false));
        });
        _scrollToBottom();
        await _speak(chatGptReply);
      } else {
        setState(() {
          _messages.add(ChatMessage(
              text: "Error: ${response.statusCode}: ${response.reasonPhrase}",
              isMe: false));
        });
      }
    } catch (error) {
      setState(() {
        _messages
            .add(ChatMessage(text: "Error: ${error.toString()}", isMe: false));
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _speak(String text) async {
    await flutterTts.stop();
    await flutterTts.speak(text);
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _startListening() async {
    if (_isSpeechAvailable && !_isListening) {
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _controller.text = result.recognizedWords;
          });
        },
      );
    }
  }

  Future<void> _stopListening() async {
    if (_isListening) {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'ChatGPT',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: Colors.black.withOpacity(0.7),
        child: Container(), // Empty drawer
      ),
      body: Container(
        color: Colors.black87,
        child: Column(
          children: [
            Expanded(
              child: Container(
                color: Colors.black87,
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    return MessageBubble(
                      message: _messages[index],
                      onSpeakPressed: () => _speak(_messages[index].text),
                    );
                  },
                ),
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.black87,
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.width * 0.04,
        ),
        child: Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Enter your message...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide(color: Colors.grey[800]!),
                    ),
                    filled: true,
                    fillColor: Colors.grey[900],
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  color: Colors.white,
                ),
                onPressed: _isListening ? _stopListening : _startListening,
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: () {
                  if (_controller.text.isNotEmpty) {
                    final message = _controller.text;
                    _controller.clear();
                    _sendMessage(message);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    flutterTts.stop();
    _controller.dispose();
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }
}

class ChatMessage {
  final String text;
  final bool isMe;

  ChatMessage({required this.text, required this.isMe});
}

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onSpeakPressed;

  const MessageBubble(
      {required this.message, required this.onSpeakPressed, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 10.0),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width *
            0.7, // Set max width to 70% of the screen
      ),
      decoration: BoxDecoration(
        color:
            message.isMe ? Colors.grey[850] : Colors.grey[700], //arker bubble
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment:
            message.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              message.text,
              style:
                  TextStyle(color: message.isMe ? Colors.white : Colors.black),
              textAlign: TextAlign.left,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.volume_up, color: Colors.white),
            onPressed: onSpeakPressed,
          ),
        ],
      ),
    );
  }
}

      //