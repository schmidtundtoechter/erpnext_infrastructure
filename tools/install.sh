docker exec -it frappe_docker-frontend-1 /bin/bash
cd /home/frappe/frappe-bench
#bench new-app my_erpnext_app
bench get-app my_erpnext_app https://github.com/mkt1/my_erpnext_app.git
bench install-app my_erpnext_app
bench migrate
bench restart
