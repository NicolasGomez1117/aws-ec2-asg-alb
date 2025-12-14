# AWS EC2 Auto Scaling Group behind an Application Load Balancer

Production-style Terraform showing a VPC-based, scaled EC2 Flask app behind an ALB.

## Architecture
- VPC `10.0.0.0/16` with 2 public + 2 private subnets across AZs
- Public subnets host the ALB and NAT Gateway; private subnets host EC2 in an ASG
- ALB listens on HTTP 80 and forwards to an EC2 target group with health checks on `/`
- Launch Template (Amazon Linux 2, `t3.micro`) installs Flask app returning `Hello from <hostname>`
- ASG desired/min/max: 2/2/5 with target-tracking scaling at ~50% CPU
- Security Groups lock traffic: Internet → ALB (80) → EC2 (80); EC2 outbound allowed for updates
- IAM instance role limited to CloudWatch Logs permissions

### Diagram
```
Internet
   |
   v
 [ALB:80] --- (Public Subnets, ALB SG)
   |
   v
[Target Group]
   |
   v
[ASG: EC2 in Private Subnets, EC2 SG] --(NAT Gateway)--> Internet (outbound for updates)
```

### Traffic Flow
Internet → Application Load Balancer → Target Group → Auto Scaling Group → EC2 instances (Flask app)  
Health checks hit `/` on port 80; unhealthy instances are replaced automatically.

## Why these choices
- **Application Load Balancer**: Layer 7 routing, health checks, and future path/host routing; terminates public ingress while keeping instances private.
- **Auto Scaling Group**: Maintains capacity, replaces unhealthy instances, and scales on CPU without manual intervention.
- **Private subnets for EC2**: Instances are not directly reachable from the internet; outbound access is via the NAT Gateway for patches and package installs.
- **Target tracking scaling**: Uses AWS-managed metric (ASGAverageCPUUtilization) to keep CPU near 50%, adding/removing instances as load changes.

## Deployment
1. Ensure AWS credentials are configured (e.g., `AWS_PROFILE`, `AWS_REGION`).
2. Review variables in `variables.tf` (defaults: region `us-east-1`, instance type `t3.micro`).
3. Initialize and apply:
   ```sh
   terraform init
   terraform apply
   ```

## Testing
After apply, grab the ALB DNS name:
```sh
ALB_URL=$(terraform output -raw alb_dns_name)
curl http://$ALB_URL
```
You should see `Hello from <hostname>`.

## Files
- `main.tf` – VPC, subnets, routing, security groups, ALB, target group, launch template, ASG, scaling policy, IAM role/profile.
- `variables.tf` – Configurable inputs (region, sizing, instance type).
- `outputs.tf` – Key outputs including ALB DNS.
- `user_data.sh` – Installs and starts the Flask app via systemd.

## AWS SAA & Junior Cloud Engineer relevance
- Demonstrates core VPC design (public/private subnets, IGW, NAT) and least-privilege security groups.
- Shows ALB + ASG pattern for resilient web services with health checks and automated scaling.
- Uses IAM roles for instances and Terraform-managed infrastructure—common topics for certs and entry-level cloud roles.

## 🛠 Instance Refreshes & Operational Learnings
This stack supports rolling updates via ASG instance refreshes. What happens:
- Launches new EC2 instances from the current launch template, waits for EC2 + ALB health checks, then terminates old nodes only after healthy replacements exist while enforcing minimum healthy capacity.
- Behavior is health-gated, not time-based; if replacements fail ALB health, the refresh stalls but traffic still flows to healthy instances.
- Terraform owns infrastructure state, but ASG/ALB own lifecycle and routing once resources exist.

Troubleshooting performed (real run):
- A replacement instance failed ALB health checks (app startup/port bind), stalling the refresh at ~50–100%.
- ASG refused to drop the last healthy instance, preserving availability.
- Fix: identify the unhealthy instance blocking the refresh, terminate it to force a new replacement, ensure user data allows the app to bind to port 80, and rerun/let refresh complete.

What this demonstrates:
- Clear separation of concerns: IaC vs. lifecycle management vs. traffic routing.
- Safe rollout guarantees enforced by AWS health checks.
- Practical steps to diagnose and unblock stalled deployments without sacrificing availability—great signal for junior cloud/DevOps interviews.
