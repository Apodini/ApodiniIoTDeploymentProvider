GREEN='\033[0;32m'
DEFAULT='\033[0m'

EXEC_PATH=".build/debug/LifxDuckieIoTDeploymentTarget"

ipAddresses=( "192.168.2.116" "192.168.2.115" "192.168.2.117" )

function reset() {
    for ipAddress in "${ipAddresses[@]}"; do
        ssh ubuntu@$ipAddress "docker stop ApodiniIoTDockerInstance; docker rm ApodiniIoTDockerInstance; docker image prune -a -f"
    done
}

echo "Testing normal deployment. Downloading images only on first run"
reset
for ((i=1;i<=10;i++)); do
    SECONDS=0
    ./$EXEC_PATH
    echo "$i - $SECONDS"$'\n' >> jass_resultTimes_normal.txt
    echo "${GREEN}\xE2\x9C\x94 RUN $i done in $SECONDS${DEFAULT}"
done

echo "Testing with docker reset. Downloading images on every run"

for ((i=1;i<=10;i++)); do
    SECONDS=0
    ./$EXEC_PATH
    echo "$i - $SECONDS"$'\n' >> jass_resultTimes_reset.txt
    echo "${GREEN}\xE2\x9C\x94 RUN $i done in $SECONDS${DEFAULT}"
    reset
done

echo "Testing without docker reset. Assuming needed images are already downloaded"

for ((i=1;i<=10;i++)); do
    SECONDS=0
    ./$EXEC_PATH
    echo "$i - $SECONDS"$'\n' >> jass_resultTimes_noReset.txt
    echo "${GREEN}\xE2\x9C\x94 RUN $i done in $SECONDS${DEFAULT}"
done


