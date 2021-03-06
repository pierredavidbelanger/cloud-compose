#!/bin/sh -x

if [ -f "/var/lib/cloud-compose/docker-compose.yml" ]; then

    cd /var/lib/cloud-compose

    # instance, region and IPs
    instance_id=$(curl -fs http://169.254.169.254/latest/meta-data/instance-id)
    region=$(curl -fs http://169.254.169.254/latest/dynamic/instance-identity/document | jq .region -r)
    public_ip=$(curl -fs http://169.254.169.254/latest/meta-data/public-ipv4)
    private_ip=$(curl -fs http://169.254.169.254/latest/meta-data/local-ipv4)
    asg_name=$(aws autoscaling describe-auto-scaling-instances --region $region --instance-ids $instance_id | jq '.AutoScalingInstances[0].AutoScalingGroupName // empty' -r)

    # env
    rm -f .env
    echo "HOST_INSTANCE_ID=$instance_id" | tee -a .env
    echo "HOST_PUBLIC_IP=$public_ip" | tee -a .env
    echo "HOST_PRIVATE_IP=$private_ip" | tee -a .env
    echo "HOST_ASG_NAME=$asg_name" | tee -a .env
    echo "HOST_HOSTNAME=$HOSTNAME" | tee -a .env
    if [ "$asg_name" != "" ]; then
        tags_json=$(aws autoscaling describe-tags --region $region --filters "Name=auto-scaling-group,Values=$asg_name")
        for key in $(echo $tags_json | jq -r ".[][].Key"); do
            value=$(echo $tags_json | jq -r ".[][] | select(.Key==\"$key\") | .Value")
            key=$(echo $key | tr '-' '_' | tr ':' '_' | tr '.' '_')
            echo "$key=$value" | tee -a .env
        done
    else
        tags_json=$(aws ec2 describe-tags --region $region --filters "Name=resource-id,Values=$instance_id")
        for key in $(echo $tags_json | jq -r ".[][].Key"); do
            value=$(echo $tags_json | jq -r ".[][] | select(.Key==\"$key\") | .Value")
            key=$(echo $key | tr '-' '_' | tr ':' '_' | tr '.' '_')
            echo "$key=$value" | tee -a .env
        done
    fi

    # docker login
    docker_username=$(aws ssm get-parameters --region $region --names docker.username | jq '.Parameters[0].Value // empty' -r)
    if [ "$docker_username" != "" ]; then
        docker_password=$(aws ssm get-parameters --region $region --names docker.password | jq '.Parameters[0].Value // empty' -r)
        docker login -u $docker_username -p $docker_password
    fi

    # docker compose
    docker-compose pull --ignore-pull-failures
    docker-compose up -d

fi