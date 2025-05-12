#!/bin/bash

DIR="Ollama-Tryout"
VENV="$DIR/venv"
SELF_DESTRUCT_TIMER=172800  # 48 Stunden in Sekunden
LOGFILE="$DIR/install.log"
OPENWEBUI_ZIP="https://github.com/openwebui/openwebui/archive/refs/heads/main.zip"

function install_dependencies {
    echo "Installiere Abhängigkeiten..." | tee -a $LOGFILE
    sudo apt update
    sudo apt install -y python3 python3-venv python3-pip build-essential libssl-dev libffi-dev python3-dev wget unzip at
}

function create_venv {
    echo "Erstelle virtuelles Environment..." | tee -a $LOGFILE
    python3 -m venv $VENV
    source $VENV/bin/activate
}

function install_ollama_openwebui {
    echo "Installiere Ollama..." | tee -a $LOGFILE
    pip install --upgrade pip
    pip install ollama

    echo "Lade OpenWebUI herunter..." | tee -a $LOGFILE
    wget -O $DIR/openwebui.zip $OPENWEBUI_ZIP
    unzip -o $DIR/openwebui.zip -d $DIR/
    mv $DIR/openwebui-main $DIR/openwebui
    rm $DIR/openwebui.zip

    echo "Installiere OpenWebUI..." | tee -a $LOGFILE
    cd $DIR/openwebui
    pip install -r requirements.txt
    cd ../../
}

function install_models {
    echo "Installiere Ollama-Modelle: LLaMA 3.2 und Mistral..." | tee -a $LOGFILE
    source $VENV/bin/activate

    # LLaMA 3.2
    ollama run llama3.2 || echo "Fehler beim Installieren von LLaMA 3.2" | tee -a $LOGFILE

    # Mistral
    ollama run mistral || echo "Fehler beim Installieren von Mistral" | tee -a $LOGFILE
}

function start_services {
    echo "Starte Ollama und OpenWebUI..." | tee -a $LOGFILE
    source $VENV/bin/activate
    nohup ollama serve &> $DIR/ollama.log &
    nohup python $DIR/openwebui/main.py &> $DIR/openwebui.log &
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
    start_services
    schedule_self_destruction
    echo "Installation abgeschlossen." | tee -a $LOGFILE
}

function uninstall {
    echo "Deinstallation gestartet..." | tee -a $LOGFILE
    pkill -f "ollama serve"
    pkill -f "main.py"
    rm -rf $DIR
    echo "Deinstallation abgeschlossen." | tee -a $LOGFILE
}

case $1 in
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
