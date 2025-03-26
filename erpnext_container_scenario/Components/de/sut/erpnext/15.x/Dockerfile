FROM frappe/erpnext:v15.54.5

# Install SSH as root
USER root
RUN apt-get update && apt-get install -y openssh-client tree

# Switch back to default user
USER frappe
