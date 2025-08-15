import 'dart:async';

import 'package:flutter/material.dart';

import 'mapView.dart';


class SplashScreen extends StatefulWidget{
  const SplashScreen({super.key});

  @override
  State<StatefulWidget> createState() {
    // TODO: implement createState
    return _SplashScreen();
  }
}
class _SplashScreen extends State<SplashScreen>{

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    Timer(Duration(seconds:2), (){
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context){
        return OpenStreetMap();
      }));
    });
  }
  @override
  Widget build(BuildContext context) {
    double deviceHeight=MediaQuery.sizeOf(context).height;
    double deviceWidth=MediaQuery.sizeOf(context).width;

    // TODO: implement build
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomLeft,
            end: Alignment.topRight,
            stops: [0,8],
            colors: [
          Color(0XFFA84BFA),
          Color(0XFFDCB8E0)
        ])
      ),
      child: Scaffold(
      backgroundColor: Colors.transparent,
        body:Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // SizedBox(height: 150,),
              Container(
                height: deviceHeight*0.40,
                width: deviceWidth*0.80,
                decoration: BoxDecoration(
                  image: DecorationImage(image: AssetImage('assets/images/Whizway2.png'),fit: BoxFit.cover,filterQuality: FilterQuality.high,)
                ),
              ),
              Text(
                 softWrap: true,
                textAlign: TextAlign.center,
                '𝑵𝒂𝒗𝒊𝒈𝒂𝒕𝒆 𝒔𝒎𝒂𝒓𝒕𝒆𝒓 𝒘𝒊𝒕𝒉 𝑾𝒉𝒊𝒛𝒘𝒂𝒚',style: TextStyle(color: Colors.white,fontSize: 25,fontWeight: FontWeight.bold,fontStyle: FontStyle.italic,fontFamily:'Philosopher'),)
            ],
          ),
        )
      ),
    );
  }
}