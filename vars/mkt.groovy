/**
 * mkt.groovy — Jenkins Shared Library for kittner.netcup pipelines
 *
 * Setup in Jenkins: Manage Jenkins → System → Global Pipeline Libraries
 *   Name:            mkt-lib
 *   Default version: main
 *   Retrieval:       Modern SCM → Git → https://github.com/mkt1/kittner.netcup.git
 *   Library path:    jenkins-lib
 *
 * Usage in Jenkinsfiles:
 *   @Library('mkt-lib@main') _
 *   ... mkt.setupSSHConfig() / mkt.backupService('traefik') / ...
 */

// ── SSH SETUP ──────────────────────────────────────────────────────────────────

/**
 * Write a single-host SSH config to ${WORKSPACE}/.ssh_config and create
 * ssh/scp wrapper scripts that force -F on every invocation.
 * Reads TARGET_HOST, TARGET_USER, TARGET_PORT, TARGET_HOSTNAME from the
 * pipeline environment.  Must be called inside
 *   withCredentials([sshUserPrivateKey(credentialsId:'host-ssh-key', keyFileVariable:'SSH_KEY')])
 */
def setupSSHConfig() {
    sh """
        # Write SSH config to workspace-local file (isolated per job — no race condition)
        echo "Host \${TARGET_HOST}"           > "\${WORKSPACE}/.ssh_config"
        echo "  User \${TARGET_USER}"         >> "\${WORKSPACE}/.ssh_config"
        echo "  Port \${TARGET_PORT}"         >> "\${WORKSPACE}/.ssh_config"
        echo "  StrictHostKeyChecking no"    >> "\${WORKSPACE}/.ssh_config"
        echo "  HostName \${TARGET_HOSTNAME}" >> "\${WORKSPACE}/.ssh_config"
        echo "  IdentityFile \${SSH_KEY}"     >> "\${WORKSPACE}/.ssh_config"
        echo "  ServerAliveInterval 60"      >> "\${WORKSPACE}/.ssh_config"
        echo "  ServerAliveCountMax 30"      >> "\${WORKSPACE}/.ssh_config"
        echo "  ConnectTimeout 30"           >> "\${WORKSPACE}/.ssh_config"
        chmod 600 "\${WORKSPACE}/.ssh_config"
        # Create ssh+scp wrappers that force -F; PATH prepended in environment{}
        # so they shadow the real binaries — no race condition
        printf '#!/bin/sh\nexec /usr/bin/ssh -F "%s/.ssh_config" "\$@"\n' "\${WORKSPACE}" > "\${WORKSPACE}/ssh"
        printf '#!/bin/sh\nexec /usr/bin/scp -F "%s/.ssh_config" "\$@"\n' "\${WORKSPACE}" > "\${WORKSPACE}/scp"
        chmod +x "\${WORKSPACE}/ssh" "\${WORKSPACE}/scp"
    """
}

/**
 * Write a two-host SSH config (TARGET_HOST + SOURCE_HOST) and create wrappers.
 * Used by reset-stage pipelines that copy data between two hosts.
 * Reads TARGET_*, SOURCE_* from the pipeline environment.
 */
def setupSSHConfigMultiHost() {
    sh """
        # Target host
        echo "Host \${TARGET_HOST}"           > "\${WORKSPACE}/.ssh_config"
        echo "  User \${TARGET_USER}"         >> "\${WORKSPACE}/.ssh_config"
        echo "  Port \${TARGET_PORT}"         >> "\${WORKSPACE}/.ssh_config"
        echo "  StrictHostKeyChecking no"    >> "\${WORKSPACE}/.ssh_config"
        echo "  HostName \${TARGET_HOSTNAME}" >> "\${WORKSPACE}/.ssh_config"
        echo "  IdentityFile \${SSH_KEY}"     >> "\${WORKSPACE}/.ssh_config"
        echo "  ServerAliveInterval 60"      >> "\${WORKSPACE}/.ssh_config"
        echo "  ServerAliveCountMax 30"      >> "\${WORKSPACE}/.ssh_config"
        echo "  ConnectTimeout 30"           >> "\${WORKSPACE}/.ssh_config"
        echo ""                              >> "\${WORKSPACE}/.ssh_config"
        # Source host
        echo "Host \${SOURCE_HOST}"           >> "\${WORKSPACE}/.ssh_config"
        echo "  User \${SOURCE_USER}"         >> "\${WORKSPACE}/.ssh_config"
        echo "  Port \${SOURCE_PORT}"         >> "\${WORKSPACE}/.ssh_config"
        echo "  StrictHostKeyChecking no"    >> "\${WORKSPACE}/.ssh_config"
        echo "  HostName \${SOURCE_HOSTNAME}" >> "\${WORKSPACE}/.ssh_config"
        echo "  IdentityFile \${SSH_KEY}"     >> "\${WORKSPACE}/.ssh_config"
        echo "  ServerAliveInterval 60"      >> "\${WORKSPACE}/.ssh_config"
        echo "  ServerAliveCountMax 30"      >> "\${WORKSPACE}/.ssh_config"
        echo "  ConnectTimeout 30"           >> "\${WORKSPACE}/.ssh_config"
        chmod 600 "\${WORKSPACE}/.ssh_config"
        printf '#!/bin/sh\nexec /usr/bin/ssh -F "%s/.ssh_config" "\$@"\n' "\${WORKSPACE}" > "\${WORKSPACE}/ssh"
        printf '#!/bin/sh\nexec /usr/bin/scp -F "%s/.ssh_config" "\$@"\n' "\${WORKSPACE}" > "\${WORKSPACE}/scp"
        chmod +x "\${WORKSPACE}/ssh" "\${WORKSPACE}/scp"
    """
}

/**
 * Write all five well-known hosts to ${WORKSPACE}/.ssh_config and create wrappers.
 * Used by services/matrix pipelines that operate across every host.
 */
def setupSSHConfigAllHosts() {
    sh """
        cat > "\${WORKSPACE}/.ssh_config" << EOF
Host sut.netcup
    User root
    Port 22
    #HostName v2202502256155316063.goodsrv.de
    HostName test.schmidtundtoechter.com
    IdentityFile \${SSH_KEY}
    ServerAliveInterval 60
    ServerAliveCountMax 30
    ConnectTimeout 30

Host aztest
    User frappe-user
    Port 22
    HostName erptest.az-it.systems
    IdentityFile \${SSH_KEY}

Host az
    User frappe-user
    Port 22
    HostName erp.az-it.systems
    IdentityFile \${SSH_KEY}

Host vepro
    User vepro
    Port 2222
    # vepro@VPRDH01
    HostName 88.198.99.206
    IdentityFile \${SSH_KEY}

EOF
        chmod 600 "\${WORKSPACE}/.ssh_config"
        printf '#!/bin/sh\nexec /usr/bin/ssh -F "%s/.ssh_config" "\$@"\n' "\${WORKSPACE}" > "\${WORKSPACE}/ssh"
        printf '#!/bin/sh\nexec /usr/bin/scp -F "%s/.ssh_config" "\$@"\n' "\${WORKSPACE}" > "\${WORKSPACE}/scp"
        chmod +x "\${WORKSPACE}/ssh" "\${WORKSPACE}/scp"
    """
}

// ── CONNECTIVITY ───────────────────────────────────────────────────────────────

/**
 * Test SSH connectivity via a scenario deploy health-check.
 * Reads TARGET_HOST, TARGET_BASE_PATH, SCENARIO_DEPLOY from env.
 * If WORKING_DIR is set, cd's into it first (needed for SUT-backed services).
 */
def testConnection(String serviceName) {
    withCredentials([sshUserPrivateKey(credentialsId: 'host-ssh-key', keyFileVariable: 'SSH_KEY')]) {
        setupSSHConfig()
        sh """
            echo "=== DEBUG: which ssh=\$(which ssh), config=\$(cat \${WORKSPACE}/.ssh_config) ==="
            cd \${WORKING_DIR:-.}
            \${SCENARIO_DEPLOY} \${TARGET_BASE_PATH}/${serviceName} test -h
            echo "=== SSH connectivity check ==="
            ssh \${TARGET_HOST} 'echo "SSH OK: \$(hostname) / \$(uptime)"'
        """
    }
}

// ── BACKUP ─────────────────────────────────────────────────────────────────────

/**
 * Run a scenario backup for the given service.
 * If WORKING_DIR is set, cd's into it first.
 */
def backupService(String serviceName) {
    withCredentials([sshUserPrivateKey(credentialsId: 'host-ssh-key', keyFileVariable: 'SSH_KEY')]) {
        setupSSHConfig()
        sh """
            cd \${WORKING_DIR:-.}
            \${SCENARIO_DEPLOY} \${TARGET_BASE_PATH}/${serviceName} backup -v
        """
    }
}

/**
 * Copy cleanupOldArchives.sh to TARGET_HOST and run it.
 * @param extraCmd  Optional additional shell command appended to the main
 *                  cleanup inside the remote ssh session (joined with ' && ').
 *                  Example: './cleanupOldArchives.sh -f -d 2 -m 3 -c monitoring'
 */
def cleanupOldBackups(String extraCmd = '') {
    withCredentials([sshUserPrivateKey(credentialsId: 'host-ssh-key', keyFileVariable: 'SSH_KEY')]) {
        setupSSHConfig()
        def extraPart = extraCmd ? " && ${extraCmd}" : ''
        sh """
            echo "🧹 Starte Backup-Cleanup auf \${TARGET_HOST} in \${BACKUP_DIR}..."
            scp \${WORKSPACE}/Units/backup/cleanupOldArchives.sh \${TARGET_HOST}:\${BACKUP_DIR}
            ssh \${TARGET_HOST} "cd \${BACKUP_DIR} && chmod +x cleanupOldArchives.sh && ./cleanupOldArchives.sh -f -d 30 -m 12${extraPart}"
        """
    }
}

/**
 * Copy cleanupDockerImages.sh to TARGET_HOST and run it.
 */
def cleanupDockerImages() {
    withCredentials([sshUserPrivateKey(credentialsId: 'host-ssh-key', keyFileVariable: 'SSH_KEY')]) {
        setupSSHConfig()
        sh """
            echo "🐳 Starte Docker Image Cleanup auf \${TARGET_HOST}..."
            scp \${WORKSPACE}/Units/backup/cleanupDockerImages.sh \${TARGET_HOST}:/tmp/
            ssh \${TARGET_HOST} 'chmod +x /tmp/cleanupDockerImages.sh && /tmp/cleanupDockerImages.sh -f && rm -f /tmp/cleanupDockerImages.sh'
        """
    }
}

// ── UPDATE ─────────────────────────────────────────────────────────────────────

/**
 * Update a service with retry logic (up to 2 attempts, 10 s pause between them).
 * On final failure attempts a recovery 'up' before raising the error.
 */
def updateService(String serviceName) {
    withCredentials([sshUserPrivateKey(credentialsId: 'host-ssh-key', keyFileVariable: 'SSH_KEY')]) {
        setupSSHConfig()
        def attempts   = 0
        def maxAttempts = 2
        while (attempts < maxAttempts) {
            attempts++
            try {
                sh """
                    echo "=== Updating ${serviceName} (Versuch ${attempts}/${maxAttempts}) ==="
                    cd \${WORKING_DIR:-.}
                    \${SCENARIO_DEPLOY} \${TARGET_BASE_PATH}/${serviceName} update -v
                    echo
                    echo "=== Restarting ${serviceName} after update with down,up ==="
                    \${SCENARIO_DEPLOY} \${TARGET_BASE_PATH}/${serviceName} down,up -v
                """
                break
            } catch (Exception e) {
                echo "Versuch ${attempts} fehlgeschlagen für ${serviceName}: ${e.message}"
                collectLogs(serviceName)
                if (attempts < maxAttempts) {
                    echo "Wiederhole in 10 Sekunden..."
                    sleep(10)
                    setupSSHConfig()  // Reconnect: SSH config may be stale after timeout
                } else {
                    echo "Zweiter Versuch fehlgeschlagen. Versuche 'up' und gebe Fehler zurück..."
                    try {
                        sh """
                            echo "=== Recovery: up for ${serviceName} ==="
                            cd \${WORKING_DIR:-.}
                            \${SCENARIO_DEPLOY} \${TARGET_BASE_PATH}/${serviceName} up -v
                        """
                    } catch (Exception e2) {
                        echo "Recovery 'up' ebenfalls fehlgeschlagen für ${serviceName}: ${e2.message}"
                        collectLogs(serviceName)
                    }
                    error("Service Update fehlgeschlagen für ${serviceName} nach 2 Versuchen")
                }
            }
        }
    }
}

/**
 * Collect diagnostic logs (container list, logs, events, disk space) for a service.
 * Safe to call from catch blocks — swallows its own errors.
 */
def collectLogs(String serviceName) {
    echo "=== Collecting diagnostic info for ${serviceName} ==="
    try {
        withCredentials([sshUserPrivateKey(credentialsId: 'host-ssh-key', keyFileVariable: 'SSH_KEY')]) {
            setupSSHConfig()
            sh """
                echo "--- Docker containers (all) ---"
                ssh \${TARGET_HOST} 'docker ps -a | grep ${serviceName} || echo "No containers found for ${serviceName}"' || true
                echo "--- Docker logs (last 50 lines per container) ---"
                ssh \${TARGET_HOST} '
                    for c in \$(docker ps -aq --filter name=${serviceName}); do
                        echo "## Logs for container \$c (\$(docker inspect --format={{.Name}} \$c)):"
                        docker logs --tail=50 \$c 2>&1 || true
                    done
                ' || true
                echo "--- Docker events (last 2 min) ---"
                ssh \${TARGET_HOST} 'timeout 10 docker events --since 2m --filter type=container 2>&1 || true' || true
                echo "--- Disk space ---"
                ssh \${TARGET_HOST} 'df -h /var/lib/docker 2>/dev/null || df -h /' || true
            """
        }
    } catch (Exception e) {
        echo "Konnte Diagnose-Infos nicht sammeln für ${serviceName}: ${e.message}"
    }
}

// ── RESET STAGE ────────────────────────────────────────────────────────────────

/**
 * Reset a stage service: sync latest backup from SOURCE_HOST, relink, restore.
 * Reads TARGET_*, SOURCE_*, BACKUP_DIR, SCENARIO_DEPLOY, TARGET_BASE_PATH from env.
 */
def resetStageScenario(String serviceName, String targetName) {
    withCredentials([sshUserPrivateKey(credentialsId: 'host-ssh-key', keyFileVariable: 'SSH_KEY')]) {
        setupSSHConfigMultiHost()
        sh """
            # Kopiere sync-latest-backup.sh zum Zielhost
            scp ./Units/backup/sync-latest-backup.sh \${TARGET_HOST}:/tmp/sync-latest-backup.sh

            # Synchronisiere neueste Backups vom Quell- zum Zielserver
            ssh \${TARGET_HOST} "/tmp/sync-latest-backup.sh \\
                --source-host \${SOURCE_HOST} \\
                --service ${serviceName} \\
                --backup-dir \${BACKUP_DIR}"

            # Erzeuge links zu den neuesten Backups
            ./Units/backup/link-backup-files.sh --remote \${TARGET_HOST} \\
                --source ${serviceName} \\
                --dest ${targetName} \\
                --backup-dir \${BACKUP_DIR} \\
                --latest \\
                --force

            # Führe Restore durch
            \${SCENARIO_DEPLOY} \${TARGET_BASE_PATH}/${targetName} down,restore,up -v
        """
    }
}

/**
 * Run an arbitrary action on the service named by SERVICE_NAME in the env.
 * Used by pipelines like sut.reset-erpnext-kunde where the service is fixed.
 */
def serviceAction(String action) {
    withCredentials([sshUserPrivateKey(credentialsId: 'host-ssh-key', keyFileVariable: 'SSH_KEY')]) {
        setupSSHConfig()
        sh """
            cd \${WORKING_DIR:-.}
            \${SCENARIO_DEPLOY} \${TARGET_BASE_PATH}/\${SERVICE_NAME} ${action} -v
        """
    }
}

// ── CHECKOUT / SETUP ───────────────────────────────────────────────────────────

/**
 * Checkout MIMS and optionally erpnext_infrastructure.
 * @param checkoutErpnext  Also checkout erpnext_infrastructure (default: false)
 * @param erpnextBranch    Branch for erpnext_infrastructure (default: 'main')
 */
def checkoutDependencies(boolean checkoutErpnext = false, String erpnextBranch = 'main') {
    dir('MIMS') {
        git url: 'https://github.com/Cerulean-Circle-GmbH/MIMS.git', branch: 'feature/mkt-fixes'
    }
    if (checkoutErpnext) {
        dir('erpnext_infrastructure') {
            git url: 'https://github.com/schmidtundtoechter/erpnext_infrastructure.git', branch: erpnextBranch
        }
    }
}

/**
 * Create symbolic links for SUT components after erpnext_infrastructure checkout.
 * @param includeCom  Also link Scenarios/com (needed for matrix/services pipelines)
 */
def linkSutComponents(boolean includeCom = false) {
    sh '''
        cd Components/de
        rm -f sut
        ln -sfn ../../erpnext_infrastructure/erpnext_container_scenario/Components/de/sut sut
        ls -la sut/
        echo "Symbolischer Link 'sut' gesetzt."
    '''
    if (includeCom) {
        sh '''
            cd Scenarios
            rm -f com
            ln -sfn ../erpnext_infrastructure/erpnext_container_scenario/Scenarios/com com
            ls -la com/
            echo "Symbolischer Link 'com' gesetzt."
        '''
    }
}
