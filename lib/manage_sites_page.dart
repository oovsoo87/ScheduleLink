// lib/manage_sites_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'models/site_model.dart';
import 'add_site_page.dart';

class ManageSitesPage extends StatefulWidget {
  const ManageSitesPage({super.key});

  @override
  State<ManageSitesPage> createState() => _ManageSitesPageState();
}

class _ManageSitesPageState extends State<ManageSitesPage> {

  Future<void> _deleteSite(String siteId) async {
    try {
      await FirebaseFirestore.instance.collection('sites').doc(siteId).delete();
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Site deleted successfully')));
      }
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting site: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Sites'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddSitePage()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('sites').orderBy('siteName').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No sites found. Add one!'));
          }

          final sites = snapshot.data!.docs.map((doc) => Site.fromFirestore(doc)).toList();

          return ListView.builder(
            itemCount: sites.length,
            itemBuilder: (context, index) {
              final site = sites[index];
              return ListTile(
                // --- NEW: Added alternating row color ---
                tileColor: index.isEven ? Theme.of(context).colorScheme.surface.withOpacity(0.5) : null,
                title: Text(site.siteName),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AddSitePage(siteToEdit: site)),
                  );
                },
                onLongPress: () {
                  showDialog(
                    context: context,
                    builder: (BuildContext ctx) {
                      return AlertDialog(
                        title: const Text('Please Confirm'),
                        content: Text('Are you sure you want to delete "${site.siteName}"?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              _deleteSite(site.id);
                              Navigator.of(ctx).pop();
                            },
                            child: const Text('Delete', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}