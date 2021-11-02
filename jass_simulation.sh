GREEN='\033[0;32m'
DEFAULT='\033[0m'

EXEC_PATH=".build/debug/LifxDuckieIoTDeploymentTarget --dump-log"

ipAddresses=( "192.168.2.120" "192.168.2.115" "192.168.2.117" )

function reset() {
    for ipAddress in "${ipAddresses[@]}"; do
        ssh ubuntu@$ipAddress "docker stop ApodiniIoTDockerInstance; docker rm ApodiniIoTDockerInstance; docker image prune -a -f"
    done
}

function stop() {
    echo "Stopping running instances"
    for ipAddress in "${ipAddresses[@]}"; do
        ssh ubuntu@$ipAddress "docker stop ApodiniIoTDockerInstance"
    done
}

function testDuckieDeployment() {
    echo "Testing if duckie deployment was successful"
    
    # Test 192.168.2.120 - should have duckie & common endpoints
    shouldFailcall=$(curl -s -o /dev/null -w "%{http_code}" 192.168.2.120:8080/v1/lifx)
    shouldSucceedCall1=$(curl -s -o /dev/null -w "%{http_code}" 192.168.2.120:8080/v1/duckie)
    shouldSucceedCall2=$(curl -s -o /dev/null -w "%{http_code}" 192.168.2.120:8080/v1/common)
    
    if [ $shouldSucceedCall1 -eq 200 ] && [ $shouldSucceedCall2 -eq 200 ] && [ $shouldFailcall -ne 200 ]; then
        echo "${GREEN}\xE2\x9C\x94 SUCCESS${DEFAULT}: Duckie Deployment was successful"
    else
        exit 1
    fi
}

function testLifxDeployment() {
    echo "Testing if lifx deployment was successful"
    errorOccurred=false
    
    # Test 192.168.2.115 - should have lifx & common endpoints
    shouldFailcall=$(curl -s -o /dev/null -w "%{http_code}" 192.168.2.115:8080/v1/duckie)
    shouldSucceedCall=$(curl -s -o /dev/null -w "%{http_code}" 192.168.2.115:8080/v1/lifx &&
            curl -s -o /dev/null -w "%{http_code}" 192.168.2.115:8080/v1/common)
    if [ $shouldSucceedCall -ne 200 ] && [ $shouldFailcall -eq 200 ]; then
        errorOccurred=true
        echo "${GREEN}\xE2\x9C\x94 SUCCESS${DEFAULT}: Duckie Deployment was successful"
    fi
    
    # Test 192.168.2.117 - should have lifx & common endpoints
    shouldFailcall=$(curl -s -o /dev/null -w "%{http_code}" 192.168.2.117:8080/v1/duckie)
    shouldSucceedCall=$(curl -s -o /dev/null -w "%{http_code}" 192.168.2.117:8080/v1/lifx &&
            curl -s -o /dev/null -w "%{http_code}" 192.168.2.117:8080/v1/common)
    if [ $shouldSucceedCall -ne 200 ] && [ $shouldFailcall -eq 200 ]; then
        errorOccurred=true
        echo "${GREEN}\xE2\x9C\x94 SUCCESS${DEFAULT}: Duckie Deployment was successful"
    fi
    
    if [ "$errorOccurred" = false ]; then
        echo "${GREEN}\xE2\x9C\x94 SUCCESS${DEFAULT}: Deployment Test was successful"
    else
        echo "${RED}Deployment Test failed!${DEFAULT}"
        exit 1
    fi
}

#echo "Testing initial deployment. Downloading images only on first run"
#for ((i=1;i<=10;i++)); do
#    reset
#    ./$EXEC_PATH
#    testLifxDeployment
#    testDuckieDeployment
#done
#
#sleep 300

echo "Testing without docker reset. Assuming needed images are already downloaded"

for ((i=1;i<=10;i++)); do
    stop
    ./$EXEC_PATH
    testLifxDeployment
    testDuckieDeployment
done


