import 'package:flutter/material.dart';

class MyDrawer extends StatelessWidget {
  static const TextStyle _menuTextColor = TextStyle(
    color: Colors.teal,
    fontSize: 14.0,
    fontWeight:FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: ListView(
        padding: EdgeInsets.all(0),
        children: <Widget>[
          UserAccountsDrawerHeader(
            accountName: Text("Nerds Stickers",
              style: TextStyle(
                fontSize:20.0,
              ),),
            accountEmail: Text("Sticker Bait Central"),
//          currentAccountPicture: Image.asset('assets/images/avatar.png'),
          ),
          ListTile(
            title: Text("Nothin doing here blud",style: _menuTextColor),
          ),
        ],
      ),
    );
  }
}