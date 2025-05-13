#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Check if script is run with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run this script with sudo or as root.${NC}"
    exit 1
fi

# Function to print colored messages
print_message() {
    echo -e "${2}${1}${NC}"
}

# Function to check if a port is in use
check_port_available() {
    local port=$1
    if netstat -tuln | grep -q ":$port "; then
        return 1 # Port is in use
    else
        return 0 # Port is available
    fi
}

# Function to find an available port starting from the given port
find_available_port() {
    local port=$1
    local max_port=$((port + 20)) # Try up to 20 ports above the starting port
    
    while [ $port -le $max_port ]; do
        if check_port_available $port; then
            echo $port
            return 0
        fi
        port=$((port + 1))
    done
    
    # Couldn't find an available port in the range
    echo "-1"
    return 1
}

# Function to install Ollama and setup system
install_ollama_direct() {
    print_message "Installing Ollama directly on your system..." "${YELLOW}"
    
    # Check if Ollama is already installed
    if command -v ollama &> /dev/null; then
        print_message "Ollama is already installed. Checking service status..." "${GREEN}"
        # Check if service is running
        if systemctl is-active --quiet ollama; then
            print_message "Ollama service is running." "${GREEN}"
        else
            print_message "Ollama service is not running. Starting it..." "${YELLOW}"
            systemctl enable ollama
            systemctl start ollama
            print_message "Ollama service started." "${GREEN}"
        fi
    else
        print_message "Installing required dependencies..." "${YELLOW}"
        apt update
        apt install -y curl
        
        print_message "Downloading and installing Ollama..." "${YELLOW}"
        curl -fsSL https://ollama.com/install.sh | bash
        
        if [ $? -ne 0 ]; then
            print_message "Failed to install Ollama. Exiting." "${RED}"
            exit 1
        fi
        
        print_message "Enabling and starting Ollama service..." "${YELLOW}"
        systemctl enable ollama
        systemctl start ollama
        
        # Wait for service to start
        sleep 5
        
        print_message "Ollama installed successfully!" "${GREEN}"
    fi
    
    # Check Ollama port
    OLLAMA_PORT=11434
    if ! check_port_available $OLLAMA_PORT; then
        print_message "Warning: Port $OLLAMA_PORT is already in use. Checking if it's Ollama..." "${YELLOW}"
        if curl -s http://localhost:$OLLAMA_PORT/api/tags > /dev/null; then
            print_message "Ollama is running on port $OLLAMA_PORT." "${GREEN}"
        else
            print_message "Port $OLLAMA_PORT is in use by another application. Finding available port..." "${YELLOW}"
            NEW_PORT=$(find_available_port $((OLLAMA_PORT + 1)))
            if [ "$NEW_PORT" == "-1" ]; then
                print_message "Could not find available port. Please stop other services using port $OLLAMA_PORT." "${RED}"
                exit 1
            fi
            print_message "Found available port: $NEW_PORT. Configuring Ollama to use this port..." "${YELLOW}"
            # Update ollama config with new port
            mkdir -p /etc/ollama
            echo "OLLAMA_HOST=127.0.0.1:$NEW_PORT" > /etc/ollama/env
            
            # Restart service
            systemctl restart ollama
            
            OLLAMA_PORT=$NEW_PORT
            print_message "Ollama configured to use port $OLLAMA_PORT." "${GREEN}"
        fi
    fi
    
    # Pull Llama3 model if not already present
    print_message "Checking if Llama3 model is installed..." "${YELLOW}"
    if ! ollama list | grep -q "llama3"; then
        print_message "Pulling Llama3 model (this may take a while)..." "${YELLOW}"
        ollama pull llama3
        print_message "Llama3 model pulled successfully!" "${GREEN}"
    else
        print_message "Llama3 model is already installed." "${GREEN}"
    fi
    
    # Create a simple test script
    SCRIPT_PATH="/usr/local/bin/ollama-test"
    print_message "Creating a test script at $SCRIPT_PATH..." "${YELLOW}"
    
    cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/bash

# Simple script to test Ollama functionality
MODEL=${1:-llama3}
PROMPT=${2:-"Hello, tell me a short interesting fact about computers."}

echo "Testing Ollama with model: $MODEL"
echo "Prompt: $PROMPT"
echo "Result:"
ollama run "$MODEL" "$PROMPT"
EOF
    
    chmod +x "$SCRIPT_PATH"
    
    # Create a Python API test script
    API_SCRIPT_PATH="/usr/local/bin/ollama-api-test"
    print_message "Creating an API test script at $API_SCRIPT_PATH..." "${YELLOW}"
    
    cat > "$API_SCRIPT_PATH" << 'EOF'
#!/usr/bin/env python3

import sys
import requests
import json

def main():
    model = sys.argv[1] if len(sys.argv) > 1 else "llama3"
    prompt = sys.argv[2] if len(sys.argv) > 2 else "Explain the basics of Linux in 3 bullet points"
    
    print(f"Testing Ollama API with model: {model}")
    print(f"Prompt: {prompt}")
    
    try:
        response = requests.post(
            "http://localhost:11434/api/generate",
            json={
                "model": model,
                "prompt": prompt,
                "stream": False
            }
        )
        
        if response.status_code == 200:
            result = response.json()
            print("\nResponse from Ollama:")
            print(result["response"])
        else:
            print(f"Error: Received status code {response.status_code}")
            print(response.text)
    except Exception as e:
        print(f"Error connecting to Ollama API: {e}")
        
if __name__ == "__main__":
    main()
EOF
    
    chmod +x "$API_SCRIPT_PATH"
    
    # Check if Python packages are available
    apt install -y python3-pip python3-requests 2>/dev/null
    
    print_message "Installation complete!" "${GREEN}"
    print_message "Ollama is running at: http://localhost:$OLLAMA_PORT" "${GREEN}"
    print_message "You can test Ollama with the following commands:" "${GREEN}"
    print_message "  - Command line: ollama run llama3 \"Your prompt here\"" "${GREEN}"
    print_message "  - Interactive chat: ollama run llama3" "${GREEN}"
    print_message "  - Test script: $SCRIPT_PATH" "${GREEN}"
    print_message "  - Python API test: $API_SCRIPT_PATH" "${GREEN}"
}

# Function to uninstall Ollama
uninstall_ollama() {
    print_message "Uninstalling Ollama..." "${YELLOW}"
    
    # Stop and disable service
    systemctl stop ollama 2>/dev/null
    systemctl disable ollama 2>/dev/null
    
    # Remove systemd service file
    rm -f /etc/systemd/system/ollama.service
    
    # Remove binary and configuration
    rm -f /usr/local/bin/ollama
    rm -rf /usr/local/lib/ollama
    rm -rf /var/lib/ollama
    rm -rf /etc/ollama
    
    # Remove test scripts
    rm -f /usr/local/bin/ollama-test
    rm -f /usr/local/bin/ollama-api-test
    
    # Reload systemd
    systemctl daemon-reload
    
    print_message "Ollama has been uninstalled." "${GREEN}"
    
    # Ask if user wants to keep models
    read -p "Do you want to remove Ollama models from /root/.ollama? (y/n): " REMOVE_MODELS
    if [[ "${REMOVE_MODELS}" == "y" ]]; then
        rm -rf /root/.ollama
        print_message "Ollama models removed." "${GREEN}"
    else
        print_message "Ollama models preserved at /root/.ollama." "${GREEN}"
    fi
    
    print_message "Uninstallation complete!" "${GREEN}"
}

# Main script
case "$1" in
    install)
        install_ollama_direct
        ;;
    uninstall)
        uninstall_ollama
        ;;
    *)
        echo "Usage: sudo $0 {install|uninstall}"
        echo ""
        echo "  install    - Install Ollama directly on the system and pull the Llama3 model"
        echo "  uninstall  - Uninstall Ollama from the system"
        exit 1
        ;;
esac

exit 0
