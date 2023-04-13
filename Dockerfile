ARG DISTRIBUTION=20.04
FROM ubuntu:${DISTRIBUTION} AS lanelet2_deps

ARG ROS_DISTRO=noetic
ARG ROS=ros
SHELL ["/bin/bash", "-c"]

# basics
RUN if [ "${ROS_DISTRO}" = "melodic" ] || [ "${ROS_DISTRO}" = "kinetic" ]; \
    then export PY_VERSION=python; \
    else export PY_VERSION=python3; \
    fi; \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        bash-completion \
        build-essential \
        curl \
        git \
        cmake \
        i${PY_VERSION} \
        keyboard-configuration \
        locales \
        lsb-core \
        nano \
        lib${PY_VERSION}-dev \
        software-properties-common \
        sudo \
        wget \
    && locale-gen en_US.UTF-8 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# locale
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    ROS_DISTRO=${ROS_DISTRO} \
    ROS=${ROS}

# install ROS
RUN echo "deb http://packages.ros.org/${ROS}/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list \
    && (apt-key adv --keyserver hkp://ha.pool.sks-keyservers.net:80 --recv-key C1CF6E31E6BADE8868B172B4F42ED6FBAB17C654 \
      || apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-key C1CF6E31E6BADE8868B172B4F42ED6FBAB17C654)

# add catkin_tools repo for python3 catkin
RUN if [ "${ROS_DISTRO}" != "melodic" ] && [ "${ROS_DISTRO}" != "kinetic" ]; \
    then add-apt-repository ppa:catkin-tools/ppa; \
    fi

# dependencies for lanelet2
RUN if [ "${ROS_DISTRO}" = "melodic" ] || [ "${ROS_DISTRO}" = "kinetic" ]; \
    then export PY_VERSION=python; \
    else export PY_VERSION=python3; \
    fi; \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        libgtest-dev \
        libboost-all-dev \
        libeigen3-dev \
        libgeographic-dev \
        libpugixml-dev \
        libboost-python-dev \
        ${PY_VERSION}-rospkg \
        ros-$ROS_DISTRO-ros-environment \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ros version specific dependencies
RUN if [ "${ROS_DISTRO}" = "melodic" ] || [ "${ROS_DISTRO}" = "kinetic" ]; \
    then export PY_VERSION=python; \
    else export PY_VERSION=python3; \
    fi; \
    if [ "$ROS" = "ros" ]; \
    then export ROS_DEPS="ros-$ROS_DISTRO-catkin ros-$ROS_DISTRO-rosbash ${PY_VERSION}-catkin-tools"; \
    else export ROS_DEPS="ros-$ROS_DISTRO-ament-cmake python3-colcon-ros ros-$ROS_DISTRO-ros2cli"; \
    fi; \
    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y $ROS_DEPS \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# create a user
RUN useradd --create-home --groups sudo --shell /bin/bash developer \
    && mkdir -p /etc/sudoers.d \
    && echo "developer ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/developer \
    && chmod 0440 /etc/sudoers.d/developer


# environment, dependencies and entry points
USER developer
ENV HOME /home/developer
WORKDIR /home/developer/workspace

RUN sudo chown -R developer:developer /home/developer \
    && echo "export ROS_HOSTNAME=localhost" > /home/developer/.bashrc \
    && echo "source /opt/ros/$ROS_DISTRO/setup.bash" >> /home/developer/.bashrc \
    && echo "source /home/developer/workspace/devel/setup.bash || true" >> /home/developer/.bashrc

# setup workspace, add dependencies
RUN if [ "$ROS" = "ros" ]; \
    then export CATKIN_INIT="source /home/developer/.bashrc && catkin init && catkin config --cmake-args -DCMAKE_BUILD_TYPE=RelWithDebInfo"; \
    fi; \
    cd /home/developer/workspace \
    && mkdir -p /home/developer/workspace/src \
    && /bin/bash -c "$CATKIN_INIT" \
    && git clone https://github.com/KIT-MRT/mrt_cmake_modules.git /home/developer/workspace/src/mrt_cmake_modules

# second stage: get the code and build the image
FROM lanelet2_deps AS lanelet2

# bring in the code
COPY --chown=developer:developer . /home/developer/workspace/src/lanelet2

# update dependencies
RUN git -C /home/developer/workspace/src/mrt_cmake_modules pull

# build
RUN if [ "$ROS" = "ros" ]; \
    then export BUILD_CMD="catkin build --no-status"; \
    else export BUILD_CMD="colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=RelWithDebInfo"; \
    fi; \
    /bin/bash -c "source /opt/ros/$ROS_DISTRO/setup.bash && env && echo $ROS && $BUILD_CMD"


# GRIT
RUN sudo apt-get update && sudo apt-get install -y python3-pip graphviz python3-pyqt5 && sudo pip3 install --upgrade python-dateutil
RUN mkdir zhaoxh && cd zhaoxh && git clone https://github.com/uoe-agents/GRIT.git GRIT && cd GRIT && pip3 install -e .
ENV MPLBACKEND=Qt5Agg

# IGP2
RUN sudo apt-get install sed
RUN cd zhaoxh && git clone https://github.com/uoe-agents/IGP2.git IGP2 && cd IGP2 && sed -i '/carla/d' requirements.txt \
    && cd igp2 && sed -i '/carla/d' __init__.py \
    && cd .. && pip3 install -e .

# OGRIT
RUN cd zhaoxh && git clone https://github.com/uoe-agents/OGRIT.git OGRIT && cd OGRIT && pip3 install -e . 
RUN  -rf /zhaoxh
