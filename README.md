## How to startup ERPNext

### Startup with devcontainer

The repository directory ```<foo>/frappe_docker```and ```<foo>/erpnext_infrastructure``` need to be in the same directory!

    cd <foo>/frappe_docker
    ../erpnext_infrastructure/dev_container_tools/frappe_docker-cleanrepository.sh
    ../erpnext_infrastructure/dev_container_tools/frappe_docker-prepare-devcontainer.sh

Now open ```frappe_docker``` folder in VS Code and reopen in devcontainer.
To reinstall and start the bench, call and follow instructions. DB Password is ```123```

    ./frappe_docker-reinstall.sh

Go to http://d-code.localhost:8000

### Startup with simple multi container setup

Get it:

    git clone https://github.com/frappe/frappe_docker.git
    cd frappe_docker

Startup ERPNext:

    docker compose -f pwd.yml up -d

Login to https://localhost:8080 :

    # user: Administrator ; password: admin

### Startup test server with MIMS

Precondition:

- `~/.ssh/config` must contain:

```
    Host sut.netcup
        User root
        Port 22
        HostName test.schmidtundtoechter.com
        IdentityFile ~/.ssh/id_rsa
```

- Test the connection: `ssh sut.netcup pwd` must run without error and give `/root`

```
    $ ssh sut.netcup pwd
    /root
```

Get the following repositories:

    git clone git@github.com:schmidtundtoechter/erpnext_infrastructure.git
    git clone git@github.com:Cerulean-Circle-GmbH/MIMS.git

Start it (on Linux/Mac or inside the devcontainer on Windows):

    cd erpnext_infrastructure/erpnext_container_scenario
    ../../MIMS/scenario.deploy com/schmidtundtoechter/test/erpnext init,up

Go to https://erpnext.test.schmidtundtoechter.com and go through the setup wizard

### Docker ps aliases for convenience

source tools/aliases.sh
