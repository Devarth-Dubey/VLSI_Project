# TPU-Inspired Systolic Array AI Accelerator

**A High-Parallelism, INT8-Based AI Hardware Accelerator Using a 2D Systolic Array Architecture**

## Overview

This project focuses on the design and implementation of a custom AI accelerator inspired by Google's Tensor Processing Unit (TPU) architecture. The accelerator is built around a two-dimensional systolic array of Processing Elements (PEs), designed to execute highly parallel matrix multiplication and multiply-accumulate (MAC) operations.

The architecture uses an **output-stationary dataflow**, where partial sums remain within individual processing elements during computation. Activations and weights propagate horizontally and vertically through the array, respectively, enabling data reuse and reducing unnecessary memory transfers.

The accelerator is designed with scalability in mind, targeting computationally intensive workloads such as:

- Deep Neural Networks (DNNs)
- Convolutional Neural Networks (CNNs)
- Transformer architectures
- Large-scale matrix multiplication
- General-purpose neural-network computations

The initial architecture uses a 4×4 systolic array with INT8 operands and INT32 accumulation, providing a foundation for larger and more parallel hardware configurations.

---

## System Architecture

The accelerator consists of a computational datapath, local memory hierarchy, control logic, address generation, and output-processing units.
<p float="center">
  <img src="Screenshot 2026-11-01 224529.png" width="77%" />
</p>

### Overall Block Diagram

```text
                   +-----------------------+
                   |     External Memory   |
                   +-----------+-----------+
                               |
                   +-----------v-----------+
                   |     DMA Controller    |
                   +-----------+-----------+
                               |
                   +-----------v-----------+
                   |    Scratchpad Memory  |
                   |                       |
                   |  Activation | Weight  |
                   +-----------+-----------+
                               |
                   +-----------v-----------+
                   | Address Generation    |
                   |         Unit          |
                   +-----------+-----------+
                               |
                   +-----------v-----------+
                   | Systolic Array        |
                   | Controller            |
                   +-----------+-----------+
                               |
                   +-----------v-----------+
                   |                       |
                   |   4 x 4 Systolic      |
                   |       Array           |
                   |                       |
                   |  +---+---+---+---+    |
                   |  |PE |PE |PE |PE |    |
                   |  +---+---+---+---+    |
                   |  |PE |PE |PE |PE |    |
                   |  +---+---+---+---+    |
                   |  |PE |PE |PE |PE |    |
                   |  +---+---+---+---+    |
                   |  |PE |PE |PE |PE |    |
                   |  +---+---+---+---+    |
                   +-----------+-----------+
                               |
                   +-----------v-----------+
                   |   Accumulator Buffer  |
                   +-----------+-----------+
                               |
                   +-----------v-----------+
                   |    Quantization Unit  |
                   +-----------+-----------+
                               |
                   +-----------v-----------+
                   |     Activation Unit   |
                   +-----------+-----------+
                               |
                   +-----------v-----------+
                   |       Output          |
                   +-----------------------+
```

---

## Architecture Components

### 1. Processing Element (PE)

The Processing Element is the fundamental computational unit of the accelerator.

Each PE performs signed multiplication followed by accumulation:

\[
ACC_{out}=ACC_{in}+(A\times B)
\]

**Features:**
- Signed INT8 multiplication.
- INT32 accumulation.
- Multiply-Accumulate (MAC) operation.
- Registered horizontal activation forwarding.
- Registered vertical weight forwarding.
- Operand-valid synchronization.
- Accumulator-clear control.

Each PE communicates with its neighboring processing elements to enable synchronized data propagation throughout the systolic array.

### 2. Systolic Array

The systolic array consists of a 2D grid of interconnected processing elements.
<p float="center">
  <img src="Screenshot 2026-10-30 164603.png" width="49%" />
</p>

**Current configuration: 4×4 (16 PEs).**

The array follows an output-stationary dataflow:

- Activations propagate horizontally.
- Weights propagate vertically.
- Partial sums are accumulated locally inside each PE.
- Valid signals synchronize operand propagation and computation.

This architecture enables parallel execution of matrix multiplication with efficient operand reuse.

### 3. Scratchpad Memory

The scratchpad memory provides local storage for input operands.

It contains separate logical memories for:

- Activation data.
- Weight data.

**Functions:**
- Stores input matrices before computation.
- Provides operand data to the accelerator controller.
- Supports programmable memory addressing.
- Reduces dependence on repeated external-memory accesses.

### 4. Systolic Array Controller

The controller coordinates the execution of matrix multiplication within the systolic array.

It is implemented using a Finite State Machine (FSM).

The controller manages:

- Activation loading.
- Weight loading.
- Processing-element accumulator clearing.
- Systolic data feeding.
- Pipeline draining.
- Result capture.
- Computation completion signaling.

### 5. Accumulator Buffer

The accumulator buffer stores the output values generated by the systolic array.

**Features:**
- INT32 storage.
- Storage for all PE outputs.
- Addressable result entries.
- Partial-sum accumulation.
- Individual result read access.
- Entry-clear functionality.

It supports the accumulation of partial results, which is important for tiled matrix multiplication.

### 6. Matrix Operation Sequencer

The matrix operation sequencer manages the execution of tiled matrix operations.

It maintains the matrix tile coordinates:

- M: Output rows.
- N: Output columns.
- K: Reduction dimension.

It coordinates the loading, clearing, computation, and storage phases required to execute a larger matrix operation using the systolic array.

### 7. Address Generation Unit (AGU)

The Address Generation Unit generates memory addresses for matrix operations.

It supports address generation for:

- Activation matrix A.
- Weight matrix B.
- Output matrix C.

The address generation follows row-major matrix organization and accounts for the matrix dimensions and tile coordinates.

### 8. DMA Controller

The DMA controller manages data transfers between external memory and local scratchpad memory.

**Functions:**
- External-memory read requests.
- External-memory write requests.
- Scratchpad memory addressing.
- Configurable transfer length.
- Handshake-based transfer control.
- Transfer completion signaling.

The DMA architecture provides the foundation for efficient movement of matrix data between memory and the computation engine.

### 9. Quantization Unit

The quantization unit converts accumulated INT32 values into INT8 output values.

**Features:**
- Configurable quantization shift.
- Rounding support.
- Signed INT8 output.
- Saturation to the INT8 range.

$$
-128 \leq Q_{out} \leq127
$$

This unit supports reduced-precision data representation for neural-network inference.

### 10. Activation Unit

The activation unit applies activation functions to the quantized output.

Supported operations include:

- Bypass.
- ReLU.
- ReLU6.

The activation mode is configurable through the control interface.

---

## Datapath Specifications

| Parameter | Architecture |
|---|---|
| Accelerator architecture | TPU-inspired |
| Computational architecture | 2D Systolic Array |
| Dataflow | Output-stationary |
| Systolic array size | 4×4 |
| Processing elements | 16 |
| Input precision | Signed INT8 |
| Multiplication | INT8 × INT8 |
| Accumulation precision | INT32 |
| Main operation | Matrix multiplication |
| Memory architecture | Scratchpad-based |
| Control architecture | FSM-based |
| Output processing | Quantization and activation |
| HDL | Verilog |

---

## Matrix Multiplication Operation

The accelerator performs matrix multiplication:

$$
C = A \times B
$$


For matrices:

$$
A \in \mathbb{R}^{M \times K}
$$

$$
B \in \mathbb{R}^{K \times N}
$$

The resulting matrix is:

$$
C \in \mathbb{R}^{M \times N}
$$

Each output element is calculated as:

$$
C_{ij} = \sum_{k=0}^{K-1} A_{ik} B_{kj}
$$

The systolic array executes this operation through parallel Multiply-Accumulate (MAC) computations across its processing elements.
For matrices larger than the physical array dimensions, the architecture uses a tiled execution approach, allowing the computational array to process smaller matrix blocks.

---

## Design and Verification

The design is developed using a modular RTL methodology.

Each major hardware component is implemented as an independent Verilog module, allowing individual verification and integration into the complete accelerator architecture.

The verification environment uses simulation testbenches to evaluate:

- Processing-element functionality.
- Systolic-array data propagation.
- Signed multiplication and accumulation.
- Scratchpad memory operations.
- Accumulator-buffer functionality.
- Controller FSM transitions.
- Matrix multiplication results.
- Quantization and activation operations.
- DMA and address-generation behavior.
- Top-level accelerator functionality.

### Simulation Results

The simulation result of the Systolic array is given below:
<p float="center">
  <img src="Screenshot 2026-10-30 114351.png" width="77%" height="50%"/>
</p>
<p float="center">
  <img src="Screenshot 2026-10-30 115754.png" width="100%" height="200%" />
</p>
The simulation of the Systolic Matrix Operation Sequencer is:
<p float="center">
  <img src="Screenshot 2026-11-01 180806.png" width="77%" />
</p>
<p float="center">
  <img src="Screenshot 2026-11-01 181120.png" width="100%" height="200% />
</p>
The simulation result for the top level integration core is:
<p float="left">
  <img src="Screenshot 2026-11-01 232524.png" width="49%" height="200%"/>
  <img src="Screenshot 2026-11-01 232537.png" width="49%" />
  <img src="Screenshot 2026-11-01 232547.png" width="49%" />
  <img src="Screenshot 2026-11-01 232556.png" width="49%" />
</p>
<p float="center">
  <img src="Screenshot 2026-11-01 232825.png" width="100%" height="250%" />
</p>
<p float="center">
  <img src="Screenshot 2026-11-01 232858.png" width="100%" height="300%" />
</p>
### FPGA Implementation Results

*To be added.*

### Performance Evaluation

*To be added.*

---

## Tools and Technologies

| Tool / Technology | Application |
|---|---|
| Verilog HDL | Hardware description |
| Icarus Verilog | RTL simulation |
| GTKWave | Waveform analysis |
| Xilinx Vivado | FPGA synthesis and implementation |
| RTL Testbenches | Functional verification |

---

## Future Architectural Extensions

The architecture is designed to provide a foundation for further hardware optimization and scalability.

Potential extensions include:

1. **Larger systolic arrays:** Scaling the PE architecture to support higher computational parallelism.
2. **Optimized memory hierarchy:** Improving bandwidth, buffering, and data reuse.
3. **CNN acceleration:** Supporting convolution and other neural-network operations.
4. **Transformer acceleration:** Supporting attention and matrix-heavy operations.
5. **Improved data movement:** Integrating optimized DMA and memory access mechanisms.
6. **FPGA optimization:** Improving resource utilization, clock frequency, and throughput.
7. **ASIC implementation:** Exploring synthesis and physical-design optimization for power, performance, and area (PPA).

---

## References and Inspiration

The project takes architectural inspiration from:

- Google TPU and systolic-array-based AI accelerator architectures.
- Output-stationary dataflow.
- Matrix multiplication accelerator architectures.
- Modern neural-network hardware acceleration techniques.

This is an independent RTL implementation and is not an official Google TPU design.

---



*Verilog | VLSI | Computer Architecture | AI Hardware Acceleration*
