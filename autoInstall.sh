#!/bin/bash
echo "
 ______________
||            ||
||            ||
||            ||
||            ||
||____________||
|______________|
 \\##############\\
  \\##############\\
   \      ____    \   
    \_____\___\____\... Iniciando Automação | @m3ss14s-2025

______________________________________________________

"

# --- Coleta de Variáveis de Ambiente ---
echo "--- Configuração do Ambiente Whaticket ---"
echo ""
echo "

"
echo ""
read -p "Digite o IP ou domínio do seu servidor (ex: meuapp.com ou 192.168.1.100): " APP_URL
read -p "Digite a porta para a API do Whaticket (ex: 8080): " PORT
read -p "Digite o usuário para o banco de dados PostgreSQL (ex: whaticket): " DB_USER
read -p "Digite a senha para o banco de dados PostgreSQL: " DB_PASS
read -p "Digite o nome do banco de dados PostgreSQL (ex: whaticket): " DB_NAME
read -p "Digite a porta do banco de dados PostgreSQL (ex: 5432): " DB_PORT
read -p "Digite o host do banco de dados PostgreSQL (geralmente localhost se rodando no mesmo servidor): " DB_HOST
read -p "Digite uma chave secreta JWT (gerar uma string aleatória longa e complexa, ex: openssl rand -base64 32): " JWT_SECRET
read -p "Digite o e-mail do administrador (para configuração inicial): " ADMIN_EMAIL
read -p "Digite a senha do administrador (para configuração inicial): " ADMIN_PASS
read -p "Digite o nome do administrador (para configuração inicial): " ADMIN_NAME

# --- Criação/Atualização do arquivo .env ---
echo "Criando ou atualizando o arquivo .env com as variáveis fornecidas..."

cat << EOF > .env
NODE_ENV=production
APP_URL=$APP_URL
PORT=$PORT
DB_DIALECT=postgres
DB_HOST=$DB_HOST
DB_USER=$DB_USER
DB_PASS=$DB_PASS
DB_NAME=$DB_NAME
DB_PORT=$DB_PORT
JWT_SECRET=$JWT_SECRET
ADMIN_EMAIL=$ADMIN_EMAIL
ADMIN_PASS=$ADMIN_PASS
ADMIN_NAME=$ADMIN_NAME
# Variáveis adicionais que podem ser necessárias dependendo da sua configuração
# VUE_APP_BASE_URL=http://$APP_URL:$PORT
# WABA_URL=https://waba.chat/
EOF

echo ".env criado com sucesso!"

# --- Deploy do Projeto Whaticket Community ---
echo "--- Iniciando o Deploy do Whaticket Community ---"

# Verifica se o diretório do projeto já existe e remove para uma instalação limpa
if [ -d "whaticket-community" ]; then
    read -p "O diretório 'whaticket-community' já existe. Deseja remover para uma instalação limpa? (s/N): " REMOVE_OLD
    if [[ "$REMOVE_OLD" =~ ^[Ss]$ ]]; then
        echo "Removendo o diretório 'whaticket-community' e caches Docker associados..."
        cd whaticket-community || exit
        docker-compose down --volumes --rmi all || true # Use || true para evitar que o script pare se o docker-compose não encontrar algo
        cd ..
        rm -rf whaticket-community
        docker system prune -a --volumes -f || true # Limpa o sistema Docker, use || true para continuar em caso de erro menor
    else
        echo "Instalação limpa cancelada. Abortando o deploy para evitar conflitos."
        exit 1
    fi
fi

echo "Clonando o repositório do Whaticket Community..."
git clone https://github.com/canove/whaticket-community.git

# Entra no diretório do projeto
cd whaticket-community || { echo "Erro: Não foi possível entrar no diretório whaticket-community."; exit 1; }

# --- Edição do Dockerfile para Correções ---
echo "Aplicando correções ao Dockerfile para compatibilidade com o ambiente de build..."

# Ajusta o FROM para Node 16 (melhor compatibilidade)
# Adiciona correções para repositórios Debian Buster e garante npm ci --force
# Assume que o Dockerfile está na raiz do projeto 'whaticket-community'
# Se o Dockerfile estiver em 'whaticket-community/backend/Dockerfile', ajuste o caminho abaixo
DOCKERFILE_PATH="/opt/whaticket/whaticket-community/backend/Dockerfile" # Altere para "backend/Dockerfile" se for o caso

if [ ! -f "$DOCKERFILE_PATH" ]; then
    echo "Erro: Dockerfile não encontrado em $DOCKERFILE_PATH. Verifique o caminho."
    exit 1
fi

sed -i 's|FROM node:14 as build-deps|FROM node:16 AS build-deps\n\n# START: Correções para compatibilidade do build\nRUN sed -i '\''s/deb.debian.org/archive.debian.org/g'\'' /etc/apt/sources.list && \\\n    sed -i '\''s/security.debian.org/archive.debian.org/g'\'' /etc/apt/sources.list\nRUN echo "deb http://archive.debian.org/debian buster main contrib non-free" > /etc/apt/sources.list.d/buster-archive.list\nRUN echo "deb http://archive.debian.org/debian-security buster/updates main contrib non-free" >> /etc/apt/sources.list.d/buster-archive.list\n# END: Correções para compatibilidade do build|g' "$DOCKERFILE_PATH"

# Substitui 'npm install' por 'npm ci --force' e garante que seja feito após copiar package.json/lock
# Esta parte é mais complexa e depende da estrutura exata do Dockerfile.
# Uma abordagem mais robusta seria copiar package.json/lock, rodar npm ci, e só depois o resto do código.
# Para evitar erros, faremos uma substituição mais simples, mas idealmente seria reestruturar.
sed -i 's|RUN npm install|COPY package.json package-lock.json ./\nRUN npm ci --force|g' "$DOCKERFILE_PATH"

# Edita o package.json para corrigir o @types/lodash
echo "Corrigindo o package.json para resolver conflitos de @types/lodash..."
# Assume que o package.json está na raiz do projeto 'whaticket-community'
# Se o package.json estiver em 'whaticket-community/backend/package.json', ajuste o caminho abaixo
PACKAGE_JSON_PATH="/opt/whaticket/whaticket-community/backend/package.json" # Altere para "backend/package.json" se for o caso

if [ ! -f "$PACKAGE_JSON_PATH" ]; then
    echo "Erro: package.json não encontrado em $PACKAGE_JSON_PATH. Verifique o caminho."
    exit 1
fi

# Remove a linha "@types/lodash" das "dependencies"
sed -i '/"@types\/lodash": "^4.17.5",/d' "$PACKAGE_JSON_PATH"

# Garante que a versão correta esteja em devDependencies (se já não estiver lá ou estiver com versão errada)
# Esta linha é mais um "ajuste fino". Se já estiver 4.14, não fará nada.
# Se precisar de uma versão específica, ajuste aqui.
sed -i 's/"@types\/lodash": ".*"/"@types\/lodash": "4.14",/' "$PACKAGE_JSON_PATH"


echo "Dockerfile e package.json ajustados."

# Copia o .env gerado para o diretório do projeto
cp ../.env ./.env

echo "Iniciando os serviços com Docker Compose..."

# Verifica se o Docker e o Docker Compose estão instalados
if ! command -v docker &> /dev/null
then
    echo "Docker não encontrado. Por favor, instale o Docker antes de continuar."
    echo "Instruções: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! command -v docker-compose &> /dev/null
then
    echo "Docker Compose não encontrado. Por favor, instale o Docker Compose antes de continuar."
    echo "Instruções: https://docs.docker.com/compose/install/"
    exit 1
fi

docker-compose up -d --build

if [ $? -eq 0 ]; then
    echo "Deploy do Whaticket Community concluído com sucesso!"
    echo "A aplicação deve estar acessível em: http://$APP_URL:$PORT"
else
    echo "Ocorreu um erro durante o deploy. Verifique os logs do Docker."
fi

echo "--- Deploy Finalizado ---"
ehco ""
echo "
███╗   ███╗██████╗ ███████╗███████╗ ██╗██╗  ██╗███████╗
████╗ ████║╚════██╗██╔════╝██╔════╝███║██║  ██║██╔════╝
██╔████╔██║ █████╔╝███████╗███████╗╚██║███████║███████╗
██║╚██╔╝██║ ╚═══██╗╚════██║╚════██║ ██║╚════██║╚════██║
██║ ╚═╝ ██║██████╔╝███████║███████║ ██║     ██║███████║
╚═╝     ╚═╝╚═════╝ ╚══════╝╚══════╝ ╚═╝     ╚═╝╚══════╝

"
echo ""
