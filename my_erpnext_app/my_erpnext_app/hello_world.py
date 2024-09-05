# my_custom_app/my_custom_app/hello_world.py

import frappe

def hello_world():
    frappe.msgprint("Hello, World!")

def modify_data():
    # Ein Beispiel für das Modifizieren von Daten in ERPNext
    doc = frappe.get_doc("ToDo", {"name": "ToDo Name"})
    doc.description = "This is updated via a plugin script!"
    doc.save()
    frappe.db.commit()