import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const kFirestoreDatabaseId = 'gotravel-rd-db';

FirebaseFirestore get firestore => FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: kFirestoreDatabaseId,
    );
