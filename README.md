## SUT DevOps Tools

SUT DevOps Tools

### License

gpl-3.0

## Some notes how to admin ERPNext

### Startup with simple multi container setup

Get it:

    git clone https://github.com/frappe/frappe_docker.git
    cd frappe_docker

Startup ERPNext:

    docker compose -f pwd.yml up -d

Login to https://localhost:8080 :

    # user: Administrator ; password: admin

### Startup with devcontainer

The repository directory ```<foo>/frappe_docker```and ```<foo>/my_erpnext_app``` need to be in the same directory!

    cd <foo>/frappe_docker
    ../my_erpnext_app/tools/frappe_docker-cleanrepository.sh
    ../my_erpnext_app/tools/frappe_docker-prepare-devcontainer.sh

Now open ```frappe_docker``` folder in VS Code and reopen in devcontainer.
To reinstall and start the bench, call and follow instructions. DB Password is ```123```

    ./frappe_docker-reinstall.sh

Go to http://d-code.localhost:8000

### Docker ps aliases for convenience

source tools/aliases.sh
