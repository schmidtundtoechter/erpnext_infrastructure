FROM frappe/erpnext:v15.42.0

# Install SSH as root
USER root
RUN apt-get update && apt-get install -y openssh-client tree

# Switch back to default user
USER frappe
