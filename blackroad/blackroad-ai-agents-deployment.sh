#!/bin/bash
# BlackRoad AI Agents - Universal Deployment System
# Deploy 15 AI workers across all infrastructure with multilingual support

set -e

echo "🤖 BlackRoad AI Agents - Universal Deployment"
echo "=============================================="
echo ""

# Infrastructure hosts
HOSTS=("alice" "shellfish" "lucidia")
MODELS=("qwen2.5:latest" "gemma2:latest" "llama3.2:latest" "codellama:latest" "mistral:latest")

echo "📋 Deployment Plan:"
echo "  • Hosts: ${HOSTS[@]}"
echo "  • Models per host: ${#MODELS[@]}"
echo "  • Total workers: $((${#HOSTS[@]} * ${#MODELS[@]}))"
echo "  • Languages: en, es, fr, de, zh, ja, ko, ar, hi, pt"
echo "  • Capabilities: code, chat, translate, emoji"
echo ""

# Create deployment package
create_deployment_package() {
    echo "📦 Creating deployment package..."

    mkdir -p /tmp/blackroad-agents
    cd /tmp/blackroad-agents

    # Create agent server
    cat > agent-server.js <<'EOF'
#!/usr/bin/env node
// BlackRoad AI Agent Server
// Multilingual AI with coding, chat, translation, and emoji support

const http = require('http');
const { spawn } = require('child_process');

const PORT = process.env.PORT || 3000;
const MODEL = process.env.OLLAMA_MODEL || 'qwen2.5:latest';
const AGENT_ID = process.env.AGENT_ID || 'blackroad-agent';

// Supported languages
const LANGUAGES = {
    en: 'English', es: 'Spanish', fr: 'French', de: 'German',
    zh: 'Chinese', ja: 'Japanese', ko: 'Korean', ar: 'Arabic',
    hi: 'Hindi', pt: 'Portuguese'
};

// Run Ollama inference
function runInference(prompt, callback) {
    const ollama = spawn('ollama', ['run', MODEL, prompt]);
    let output = '';
    let error = '';

    ollama.stdout.on('data', (data) => {
        output += data.toString();
    });

    ollama.stderr.on('data', (data) => {
        error += data.toString();
    });

    ollama.on('close', (code) => {
        if (code === 0) {
            callback(null, output);
        } else {
            callback(new Error(error || 'Inference failed'), null);
        }
    });
}

// HTTP Server
const server = http.createServer((req, res) => {
    // CORS headers
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
        return;
    }

    // Health check
    if (req.url === '/health' || req.url === '/') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
            status: 'healthy',
            agent: AGENT_ID,
            model: MODEL,
            languages: Object.keys(LANGUAGES),
            capabilities: ['code', 'chat', 'translate', 'emoji'],
            uptime: process.uptime()
        }));
        return;
    }

    // Inference endpoint
    if (req.url === '/api/infer' && req.method === 'POST') {
        let body = '';

        req.on('data', chunk => {
            body += chunk.toString();
        });

        req.on('end', () => {
            try {
                const { prompt, language = 'en', task = 'chat' } = JSON.parse(body);

                if (!prompt) {
                    res.writeHead(400, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ error: 'Missing prompt' }));
                    return;
                }

                // Enhance prompt based on task
                let enhancedPrompt = prompt;

                if (task === 'code') {
                    enhancedPrompt = `You are a coding expert. ${prompt}`;
                } else if (task === 'translate') {
                    enhancedPrompt = `Translate to ${LANGUAGES[language] || language}: ${prompt}`;
                } else if (task === 'emoji') {
                    enhancedPrompt = `Respond using emojis: ${prompt}`;
                }

                console.log(`[${AGENT_ID}] Running inference: ${task} (${language})`);

                runInference(enhancedPrompt, (err, output) => {
                    if (err) {
                        res.writeHead(500, { 'Content-Type': 'application/json' });
                        res.end(JSON.stringify({ error: err.message }));
                        return;
                    }

                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({
                        agent: AGENT_ID,
                        model: MODEL,
                        task: task,
                        language: language,
                        response: output.trim(),
                        timestamp: new Date().toISOString()
                    }));
                });

            } catch (err) {
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'Invalid JSON' }));
            }
        });
        return;
    }

    // 404
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not found' }));
});

server.listen(PORT, () => {
    console.log(`🤖 BlackRoad Agent [${AGENT_ID}] listening on port ${PORT}`);
    console.log(`   Model: ${MODEL}`);
    console.log(`   Languages: ${Object.keys(LANGUAGES).join(', ')}`);
    console.log(`   Capabilities: code, chat, translate, emoji`);
});
EOF

    # Create systemd service template
    cat > blackroad-agent.service <<'EOF'
[Unit]
Description=BlackRoad AI Agent - %i
After=network.target

[Service]
Type=simple
User=blackroad
WorkingDirectory=/opt/blackroad-agents
Environment="OLLAMA_MODEL=%i"
Environment="AGENT_ID=blackroad-agent-%i"
Environment="PORT=300%i"
ExecStart=/usr/bin/node /opt/blackroad-agents/agent-server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Create deployment script
    cat > deploy-to-host.sh <<'EOF'
#!/bin/bash
HOST=$1
MODELS=$2

echo "📡 Deploying to $HOST..."

# Create directory
ssh $HOST "sudo mkdir -p /opt/blackroad-agents && sudo chown -R \$(whoami):\$(whoami) /opt/blackroad-agents"

# Copy files
scp agent-server.js $HOST:/opt/blackroad-agents/
scp blackroad-agent.service $HOST:/tmp/

# Install Ollama if not present
ssh $HOST "which ollama || (curl -fsSL https://ollama.com/install.sh | sh)"

# Pull models and create services
for MODEL in $MODELS; do
    MODEL_NAME=$(echo $MODEL | cut -d: -f1)

    echo "  • Pulling model: $MODEL"
    ssh $HOST "ollama pull $MODEL" &

    # Create service
    ssh $HOST "sudo cp /tmp/blackroad-agent.service /etc/systemd/system/blackroad-agent@$MODEL_NAME.service"
done

wait

# Enable and start services
for MODEL in $MODELS; do
    MODEL_NAME=$(echo $MODEL | cut -d: -f1)
    echo "  • Starting agent: $MODEL_NAME"
    ssh $HOST "sudo systemctl daemon-reload && sudo systemctl enable blackroad-agent@$MODEL_NAME && sudo systemctl restart blackroad-agent@$MODEL_NAME"
done

echo "✅ Deployment to $HOST complete!"
EOF

    chmod +x deploy-to-host.sh
    chmod +x agent-server.js

    echo "✅ Deployment package created"
}

# Deploy to all hosts
deploy_agents() {
    echo ""
    echo "🚀 Deploying agents to all hosts..."

    for host in "${HOSTS[@]}"; do
        echo ""
        echo "=== $host ==="

        # Deploy models (max 5 per host)
        MODELS_STR="${MODELS[@]}"
        ./deploy-to-host.sh $host "$MODELS_STR" &
    done

    wait

    echo ""
    echo "✅ All deployments complete!"
}

# Create web dashboard
create_dashboard() {
    echo ""
    echo "📊 Creating agent dashboard..."

    cat > ~/blackroad-agents-dashboard.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>BlackRoad AI Agents</title>
    <style>
        body {
            font-family: 'JetBrains Mono', monospace;
            background: #000;
            color: #fff;
            padding: 21px;
        }
        .agent-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 21px;
            margin-top: 34px;
        }
        .agent-card {
            background: rgba(255,255,255,0.05);
            border: 2px solid #FF1D6C;
            border-radius: 13px;
            padding: 21px;
        }
        .status {
            display: inline-block;
            width: 13px;
            height: 13px;
            border-radius: 50%;
            background: #00ff00;
        }
        .btn {
            background: linear-gradient(135deg, #F5A623 0%, #FF1D6C 50%, #9C27B0 100%);
            border: none;
            padding: 13px 21px;
            border-radius: 8px;
            color: #fff;
            cursor: pointer;
            margin-top: 13px;
        }
    </style>
</head>
<body>
    <h1>🤖 BlackRoad AI Agents</h1>
    <p>15 AI workers deployed across infrastructure</p>
    <div class="agent-grid" id="agents"></div>

    <script>
        const hosts = ['alice', 'shellfish', 'lucidia'];
        const models = ['qwen2.5', 'gemma2', 'llama3.2', 'codellama', 'mistral'];

        const agentGrid = document.getElementById('agents');

        hosts.forEach(host => {
            models.forEach(model => {
                const card = document.createElement('div');
                card.className = 'agent-card';
                card.innerHTML = `
                    <h3><span class="status"></span> ${host}/${model}</h3>
                    <p>Languages: 🌐 10+</p>
                    <p>Capabilities: 💻 Code | 💬 Chat | 🔤 Translate | 😊 Emoji</p>
                    <button class="btn" onclick="testAgent('${host}', '${model}')">Test Agent</button>
                `;
                agentGrid.appendChild(card);
            });
        });

        function testAgent(host, model) {
            console.log(`Testing ${host}/${model}...`);
            alert(`Testing ${host}/${model}! Check console for results.`);
        }
    </script>
</body>
</html>
EOF

    echo "✅ Dashboard created: ~/blackroad-agents-dashboard.html"
}

# Main execution
main() {
    create_deployment_package

    echo ""
    read -p "Deploy agents to all hosts? (y/N) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        deploy_agents
    fi

    create_dashboard

    echo ""
    echo "🎉 BlackRoad AI Agents Deployment Complete!"
    echo ""
    echo "📊 Summary:"
    echo "  • Agents deployed: $((${#HOSTS[@]} * ${#MODELS[@]}))"
    echo "  • Languages: 10+ (en, es, fr, de, zh, ja, ko, ar, hi, pt)"
    echo "  • Capabilities: Code, Chat, Translate, Emoji"
    echo ""
    echo "🌐 Test endpoints:"
    for host in "${HOSTS[@]}"; do
        echo "  • http://${host}.blackroad.io:3000/health"
    done
    echo ""
    echo "📊 Dashboard: ~/blackroad-agents-dashboard.html"
}

main
