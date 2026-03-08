# RTL to GDSII Design of Control Unit for EVM

## Project Overview

This project focuses on the **Register Transfer Level (RTL) design** of the **Control Unit** for an **Electronic Voting Machine (EVM)**. The control unit plays a crucial role in the functioning of an EVM, controlling the flow of data, operation of the machine, and ensuring secure and accurate voting results.

The design is implemented in **Verilog** , and the primary goal is to demonstrate how a control unit in a voting machine can be efficiently designed using RTL principles and then converted to its GDSII file.

## Table of Contents

1. [Introduction](#introduction)
2. [Design Architecture](#design-architecture)
3. [Features](#features)
4. [Getting Started](#getting-started)
5. [Pre requisites](#prerequisites)
6. [Usage](#usage)
7. [Project Structure](#project-structure)
8. [Testing](#testing)


## Introduction
![Text Image 1](https://www.canva.com/design/DAGmNY0U0AA/zh2tG8UmWX4rMsBNsRW-5g/view?utm_content=DAGmNY0U0AA&utm_campaign=designshare&utm_medium=link&utm_source=viewer)
The **Control Unit** (CU) of the **EVM** is responsible for organising various functional components, ensuring that voting operations are securely carried out. The design involves:

- **Voting data input** {voter selection from Ballot unit(which is considered as a 16:4 encoder), button presses on the CU itself}
- **Memory components** (to store voter information and vote tally)
- **Proper Sequencr of flow** (Algorithm for the correct movement of data and to ensure security)
- **Display output** (status and results)

This project is aimed at providing a basic yet robust understanding of how RTL can be used to implement a control unit that coordinates all these processes and enhances some features compared to the current worling system.

## Design Architecture

The architecture consists of the following modules:

- **Control Logic:** Manages the sequential flow of operations within the EVM.
- **Data Path:** Handles the data movement between the registers, memory, and output.
- **Clock Control:** Synchronizes the operations of the control unit and the other components.
- **Input/Output Interface:** Facilitates communication with external buttons and the display.

## Features:

- **Finite State Machine (FSM):** The control unit uses an FSM for managing the sequence of operations during a vote.
- **Getting Result:** The project is divided into several modules for better scalability and reusability.
- **Secure Operation:** As it is made in RTL, each stage is seperated from each others and especially some states like Close, Wait and Result can't come out from their state to perform other task if some specific path is not followed.

## Getting Started

### Prerequisites

Before you start, ensure you have the following installed:

- **Verilog Compiler/Simulator** (e.g., ModelSim, Xilinx Vivado, or any simulator of your choice)
- **Git** for version control
- **Any text editor/IDE** for coding (e.g., VS Code, Sublime Text, etc.)
- **Any RTL to GDSII tool** for conversion (e.g., Qflow, OpenLane, etc.)
