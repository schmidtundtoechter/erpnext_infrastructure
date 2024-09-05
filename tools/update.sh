docker exec -it frappe_docker-frontend-1 /bin/bash
cd /home/frappe/frappe-bench/apps/my_erpnext_app
git pull
cd /home/frappe/frappe-bench
bench migrate
bench build
bench clear-cache
bench restart
