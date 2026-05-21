#!/bin/bash

echo "=============================="
echo " SERVER HEALTH CHECK"
echo "=============================="
echo ""

echo "CPU / LOAD:"
echo "-----------"
nproc | awk '{print "CPU Cores: " $1}'
uptime
echo ""

echo "MEMORY:"
echo "-------"
free -h
echo ""

echo "DISK:"
echo "-----"
df -h /
echo ""

echo "TOP PROCESSES BY MEMORY:"
echo "------------------------"
ps aux --sort=-%mem | awk 'NR<=10 {print $1, $2, $3"%CPU", $4"%MEM", $11}'
echo ""

echo "TOP PROCESSES BY CPU:"
echo "---------------------"
ps aux --sort=-%cpu | awk 'NR<=10 {print $1, $2, $3"%CPU", $4"%MEM", $11}'
echo ""

echo "DOCKER CONTAINERS USAGE:"
echo "------------------------"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"
echo ""

echo "DOCKER DISK USAGE:"
echo "------------------"
docker system df
echo ""

echo "REDIS CONTAINERS:"
echo "-----------------"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -i redis || true
echo ""

echo "POSTGRES CONTAINERS:"
echo "--------------------"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -i postgres || true
echo ""

echo "N8N CONTAINERS:"
echo "---------------"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -i n8n || true
echo ""

echo "=============================="
echo " CHECK COMPLETE"
echo "=============================="
