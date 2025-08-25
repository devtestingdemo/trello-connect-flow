#!/bin/bash

# Production deployment script for Trello Connect Flow (Unified Frontend + Backend)
set -e

echo "🚀 Starting production deployment of Trello Connect Flow..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "docker-compose.unified.yml" ]; then
    print_error "Please run this script from the project root directory"
    exit 1
fi

# Step 1: Check if .env.production exists
if [ ! -f ".env.production" ]; then
    print_warning ".env.production not found. Creating template..."
    cat > .env.production << EOF
FLASK_RUN_HOST=0.0.0.0
FLASK_RUN_PORT=5000
REDIS_PORT=6379
SECRET_KEY=your-production-secret-key-change-this
SQLALCHEMY_DATABASE_URI=sqlite:///instance/users.db
FRONTEND_URL=https://boards.norgayhrconsulting.com.au
FLASK_ENV=production
FLASK_DEBUG=0
FLASK_APP=app.py
EOF
    print_warning "Please edit .env.production with your actual values before continuing"
    print_warning "Especially change the SECRET_KEY to a secure random string"
    exit 1
fi

# Step 2: Build frontend for production
print_status "Building frontend for production..."
cd frontend
npm install
npm run build
cd ..

# Step 3: Copy production env to backend for Docker build
print_status "Copying environment file to backend..."
cp .env.production backend/.env

# Step 4: Create instance directory with proper permissions
print_status "Setting up database directory..."
mkdir -p backend/instance
chmod 755 backend/instance

# Step 5: Initialize database
print_status "Initializing database..."
cd backend
python3 -c "
from app_factory import create_app
from db import db
app, q = create_app()
with app.app_context():
    db.create_all()
    print('Database initialized successfully')
"
cd ..

# Step 6: Stop existing containers and clean up orphans
print_status "Stopping existing containers and cleaning up orphans..."
docker compose -f docker-compose.unified.yml down --remove-orphans || true

# Force remove any conflicting containers
print_status "Removing any conflicting containers..."
docker ps -a --filter "name=trello-connect-flow" --format "{{.Names}}" | xargs -r docker rm -f
docker ps -a --filter "publish=5000" --format "{{.Names}}" | xargs -r docker rm -f
docker ps -a --filter "publish=6379" --format "{{.Names}}" | xargs -r docker rm -f

# Step 7: Build and start containers
print_status "Building and starting production containers..."
docker compose -f docker-compose.unified.yml up -d --build

# Step 8: Wait for services to be ready
print_status "Waiting for services to be ready..."
sleep 15

# Step 9: Check if services are running
print_status "Checking service status..."
if docker compose -f docker-compose.unified.yml ps | grep -q "Up"; then
    print_status "✅ Services are running successfully!"
else
    print_error "❌ Some services failed to start. Check logs:"
    docker compose -f docker-compose.unified.yml logs
    exit 1
fi

# Step 10: Test unified application
print_status "Testing unified application..."
sleep 5  # Give the app time to start
if curl -s http://localhost:5000/api/users > /dev/null; then
    print_status "✅ API is responding correctly!"
else
    print_warning "⚠️  API might not be ready yet. Check logs:"
    docker compose -f docker-compose.unified.yml logs backend
fi

# Test frontend served by backend
if curl -s http://localhost:5000 > /dev/null; then
    print_status "✅ Frontend is being served by backend!"
else
    print_warning "⚠️  Frontend might not be ready yet. Check logs:"
    docker compose -f docker-compose.unified.yml logs backend
fi

print_status "🎉 Production deployment completed!"
print_status "Your application is now running at:"
echo "  - Application: http://localhost:5000 (Frontend + Backend)"
echo "  - API endpoints: http://localhost:5000/api/*"
echo "  - Redis: localhost:6379"

print_status "Next steps for production:"
echo "1. Set up reverse proxy (nginx/Apache) to forward requests to localhost:5000"
echo "2. Configure SSL certificate with Let's Encrypt"
echo "3. Set up domain DNS to point to this server"
echo "4. Configure firewall to allow HTTP/HTTPS traffic"

print_status "Useful commands:"
echo "  - View logs: docker compose -f docker-compose.unified.yml logs -f"
echo "  - Stop services: docker compose -f docker-compose.unified.yml down"
echo "  - Restart services: docker compose -f docker-compose.unified.yml restart"
echo "  - Update and redeploy: ./deploy-production.sh"

# Show running containers
echo ""
print_status "Running containers:"
docker compose -f docker-compose.unified.yml ps 