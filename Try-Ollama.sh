#!/bin/bash

DIR="$HOME/Ollama-Tryout"
VENV="$DIR/venv"
SELF_DESTRUCT_TIMER=172800  # 48 Stunden in Sekunden
LOGFILE="$DIR/install.log"
OPENWEBUI_ZIP="https://github.com/openwebui/openwebui/archive/refs/heads/main.zip"

function install_dependencies {
    echo "Installiere Abhängigkeiten..." | tee -a $LOGFILE
    sudo apt update
    sudo apt install -y python3 python3-venv python3-pip build-essential libssl-dev libffi-dev python3-dev wget unzip at curl
}

function create_venv {
    echo "Erstelle virtuelles Environment..." | tee -a $LOGFILE
    python3 -m venv $VENV
    source $VENV/bin/activate
}

function install_ollama_openwebui {
    echo "Installiere Ollama..." | tee -a $LOGFILE
    curl -fsSL https://ollama.com/install.sh | sh
    
    echo "Lade OpenWebUI herunter..." | tee -a $LOGFILE
    mkdir -p $DIR
    wget -O $DIR/openwebui.zip $OPENWEBUI_ZIP
    unzip -o $DIR/openwebui.zip -d $DIR/
    mv $DIR/openwebui-main $DIR/openwebui
    rm $DIR/openwebui.zip

    echo "Installiere OpenWebUI..." | tee -a $LOGFILE
    cd $DIR/openwebui
    pip install -r requirements.txt
    cd - > /dev/null
}

function install_models {
    echo "Installiere Ollama-Modelle: LLaMA 3.2 und Mistral..." | tee -a $LOGFILE
    # Start Ollama server for model installation
    ollama serve > /dev/null 2>&1 &
    OLLAMA_PID=$!
    # Wait for Ollama server to start
    sleep 5
    
    # LLaMA 3.2
    ollama pull llama3.2 || echo "Fehler beim Installieren von LLaMA 3.2" | tee -a $LOGFILE

    # Mistral
    ollama pull mistral || echo "Fehler beim Installieren von Mistral" | tee -a $LOGFILE
    
    # Kill the temporary Ollama server
    kill $OLLAMA_PID
    wait $OLLAMA_PID 2>/dev/null
}

function create_service_files {
    echo "Erstelle systemd Service-Dateien..." | tee -a $LOGFILE
    
    # Ollama service
    sudo tee /etc/systemd/system/ollama.service > /dev/null << EOF
[Unit]
Description=Ollama Service
After=network.target

[Service]
ExecStart=/usr/local/bin/ollama serve
Restart=always
User=$USER
Group=$USER

[Install]
WantedBy=multi-user.target
EOF

    # OpenWebUI service
    sudo tee /etc/systemd/system/openwebui.service > /dev/null << EOF
[Unit]
Description=OpenWebUI Service
After=ollama.service
Requires=ollama.service

[Service]
ExecStart=$VENV/bin/python $DIR/openwebui/main.py
WorkingDirectory=$DIR/openwebui
Restart=always
User=$USER
Group=$USER
Environment="PATH=$VENV/bin:/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    sudo systemctl daemon-reload
}

function start_services {
    echo "Starte Ollama und OpenWebUI als systemd Services..." | tee -a $LOGFILE
    
    sudo systemctl enable ollama.service
    sudo systemctl start ollama.service
    
    # Give Ollama time to start
    sleep 5
    
    sudo systemctl enable openwebui.service
    sudo systemctl start openwebui.service
    
    echo "Services gestartet. OpenWebUI sollte in wenigen Sekunden unter http://localhost:8080 verfügbar sein." | tee -a $LOGFILE
}

function schedule_self_destruction {
    echo "Skript wird in 48 Stunden automatisch deinstalliert..." | tee -a $LOGFILE
    echo "bash $0 Uninstall" | at now + 48 hours
}

function install {
    echo "Installation gestartet..." | tee -a $LOGFILE
    mkdir -p $DIR
    install_dependencies
    create_venv
    install_ollama_openwebui
    install_models
    create_service_files
    start_services
    schedule_self_destruction
    echo "Installation abgeschlossen." | tee -a $LOGFILE
}

function uninstall {
    echo "Deinstallation gestartet..." | tee -a $LOGFILE
    
    # Stop and disable services
    sudo systemctl stop openwebui.service 2>/dev/null
    sudo systemctl disable openwebui.service 2>/dev/null
    sudo systemctl stop ollama.service 2>/dev/null
    sudo systemctl disable ollama.service 2>/dev/null
    
    # Remove service files
    sudo rm -f /etc/systemd/system/ollama.service
    sudo rm -f /etc/systemd/system/openwebui.service
    sudo systemctl daemon-reload
    
    # Clean up Ollama binaries
    sudo rm -f /usr/local/bin/ollama
    
    # Remove installation directory
    rm -rf $DIR
    
    echo "Deinstallation abgeschlossen." | tee -a $LOGFILE
}

case "$1" in
    Install)
        install
        ;;
    Uninstall)
        uninstall
        ;;
    *)
        echo "Ungültige Option. Verwende 'Install' oder 'Uninstall'."
        ;;
esac

exit 0 
