# Car CI/CD

The car is a GitHub Actions self-hosted runner. It connects outbound to GitHub,
so it does not need a fixed address, public SSH port, DDNS, or LAN discovery.

## One-time setup on the car

1. In the GitHub repository, open `Settings > Actions > Runners > New self-hosted runner`.
2. Choose the car's Linux CPU architecture and run the generated download and
   `config.sh` commands on the car. Assign the label `car` when prompted.
3. Install the runner service using the commands printed by GitHub (`sudo ./svc.sh install` and `sudo ./svc.sh start`).
4. Clone this repository to `$HOME/zihan-car` on the car, then run:

   ```bash
   cd ~/zihan-car
   chmod +x scripts/deploy-car.sh scripts/setup-car-service.sh
   ./scripts/setup-car-service.sh
   ```

   Set `ROS_SETUP` before this command when the ROS setup file is not
   `/opt/ros/noetic/setup.bash`, for example:

   ```bash
   ROS_SETUP=/opt/ros/humble/setup.bash ./scripts/setup-car-service.sh
   ```

5. Create the `car-production` environment under `Settings > Environments` and
   add required reviewers if deployment approval is needed.

Pushes to `master` validate the ROS bridge, validate HarmonyOS project metadata, and then
deploy the bridge to the registered car runner. Pull requests run validation and
validation only.

The workflow does not produce a HAP because the public HarmonyOS SDK setup action previously referenced here no longer exists. Use a DevEco-capable dedicated runner when cloud HAP builds are required.
