# Event-driven autoscaling with KEDA in EKS

The repository contains the sample templates to deploy KEDA in an EKS cluster and test the SQS based event driven autoscaling.

## Prerequisites

- An active AWS account
- IAM permissions – The IAM security principal that you're using must have permissions to work with Amazon EKS IAM roles and service-linked roles, AWS CloudFormation, and a VPC and related resources.
- Install [kubectl](https://kubernetes.io/docs/tasks/tools/),[eksctl](https://eksctl.io/introduction/?h=install#installation),[AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) and [Helm](https://helm.sh/docs/intro/install/) in your local machine or in the CICD setup

### Creating an EKS cluster

The cluster creation example is based on [eksctl](https://eksctl.io/introduction/) which is a simple CLI tool for creating and managing clusters on EKS.EKS Clusters can be deployed and managed with a number of solutions including Terraform, Cloudformation,AWS Console and AWS CLI.

The eksctl tool uses CloudFormation under the hood, creating one stack for the EKS master control plane and another stack for the worker nodes.eksctl creates a new vpc named `eksctl-keda-demo-cluster-cluster/VPC` in the target region (if you need to use custom vpc configuration then refer to [link](https://eksctl.io/usage/creating-and-managing-clusters/#:~:text=If%20you%20needed%20to%20use%20an%20existing%20VPC%2C%20you%20can%20use%20a%20config%20file%20like%20this%3A))

Run the below command to create a new cluster in the `us-west-2` region and refer to `eks/keda-demo-cluster.yaml` for sample cluster configuration; expect this to take around 20 minutes.

```bash
eksctl create cluster -f eks/keda-demo-cluster.yaml
```

<!-- The sample cluster is also deployed with the EKS Pod Identity add-on which provides the ability to manage credentials for your applications, similar to the way that Amazon EC2 instance profiles provide credentials to Amazon EC2 instances. Instead of creating and distributing your AWS credentials to the containers or using the Amazon EC2 instance's role, you associate an IAM role with a Kubernetes service account and configure your Pods to use the service account. Refer to the [official documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) for more details. -->

### Setup IAM roles for service accounts

We will use [IAM roles for service accounts](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) to provide applications including KEDA to access AWS APIs.(EKS Pod Identities)[https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html] is currently not supported in KEDA.

The cluster has an OpenID Connect (OIDC) issuer URL associated with it. To use AWS Identity and Access Management (IAM) roles for service accounts, an IAM OIDC provider must exist for your cluster's OIDC issuer URL.

Run the below command to retrieve the OIDC arn details and update the `keda-resources/keda-operator-iam.yaml` cloudformation template.

```bash
aws iam list-open-id-connect-providers
```

Deploy the CloudFormation template for the IAM resources. Include the AWS account number and OIDC URL from the above results.

```bash
aws cloudformation deploy --template-file keda-resources/keda-operator-iam.yaml --stack-name keda-operator-iam --capabilities CAPABILITY_AUTO_EXPAND CAPABILITY_NAMED_IAM CAPABILITY_IAM  --parameter-overrides EKSClusterOIDCURL="<<EKS-CLUSTER-OIDC-URL-WITHOUT-HTTPS-IN-URL>>"
```

Example:

```bash
aws cloudformation deploy --template-file keda-resources/keda-operator-iam.yaml --stack-name keda-operator-iam --capabilities CAPABILITY_AUTO_EXPAND CAPABILITY_NAMED_IAM CAPABILITY_IAM --parameter-overrides EKSClusterOIDCURL="oidc.eks.us-west-2.amazonaws.com/id/97E370F5123E8A876752C2945BDDF59A"
```

<!-- Create a simple IAM policy for the keda operator to query the SQS attributes which are required for the HPA.

    aws iam create-policy \
        --policy-name keda-operator-policy \
        --policy-document file://KEDA/01-keda-operator-iam-policy-for-sqs.json

Create a pod identity association for KEDA.

    eksctl create podidentityassociation \
        --cluster keda-demo-cluster \
        --namespace keda \
        --service-account-name keda-operator \
        --permission-policy-arns="arn:aws:iam::<<AWS-ACCOUNT-NAME>:policy/keda-operator-policy"

    eksctl create podidentityassociation \
        --cluster keda-demo-cluster \
        --namespace keda \
        --service-account-name keda-operator \
        --permission-policy-arns="arn:aws:iam::317630533282:policy/keda-operator-policy" -->

### Deploy KEDA

Deploying KEDA with [Helm](https://keda.sh/docs/2.12/deploy/#helm) is very simple.

Add and Update Helm repo
```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
```

Install keda Helm chart and use the IAM role ARN from the above cloudformation stack.
```bash
helm upgrade -install keda kedacore/keda \
    --namespace keda \
    --set 'serviceAccount.annotations.eks\.amazonaws\.com\/role-arn'="<<KEDA-IAM-ROLE-ARN-FROM-PREVIOUS-STEPS>" \
    --create-namespace \
    --debug \
    --wait
```
Example:

```bash
    helm upgrade -install keda kedacore/keda \
    --namespace keda \
    --set 'serviceAccount.annotations.eks\.amazonaws\.com\/role-arn'="arn:aws:iam::317630533282:role/Keda-Operator" \
    --create-namespace \
    --debug \
    --wait
```
Run the below command to verify the keda installation and ensure the KEDA pods are running fine.

```bash
kubectl get pods -n keda
```
### Create a sample SQS Queue

Run the below command to create a sample SQS queue to publish the test messages.

```bash
aws sqs create-queue --queue-name keda-test-queue --region <AWS-REGION>
```
### Deploy a sample application

The sample application is based on nginx to demo the dynamic scaling of deployment.

```bash
kubectl create deployment sqs-test-app --image nginx --namespace default --replicas 1
```
Deploy the KEDA resources necessary for the autoscaling and update `queueURL`, `awsRegion` values.

- scaledObject: sets the HPA rules. We’re using the SQS scaler

- triggerAuthentication: tells the scaledObject how to authenticate to AWS.

```bash
kubectl apply -f keda-resources/scaledObject.yaml
```

### Test the setup

Now we can send some messages and see if our deployment scales! Use the script `send-messages.sh` to send messages to the queue and monitor the deployment.
KEDA will automatically scale the number of replicas to zero when no messages are available in the queue.

https://github.com/ChimbuChinnadurai/keda-eks-event-driven-autoscaling-demo/assets/46873109/3e5ef49d-5c99-40a6-84a7-357528edbff7
