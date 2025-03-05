# 5-Stage Pipelined RISC-V Processor
Overview
This project implements a 5-stage pipelined RISC-V processor, designed to handle data hazards, control hazards, and structural hazards efficiently. The processor features forwarding logic, static branch prediction, and flushing mechanisms to improve performance.

Features
5-stage pipeline: Instruction Fetch (IF), Instruction Decode (ID), Execute (EX), Memory (MEM), Write Back (WB)
Hazard Handling:
Data Hazard: Implemented forwarding logic to reduce stalls.
Control Hazard: Implemented static branch prediction.
Structural Hazard: Managed resource contention effectively.
Flushing Mechanism: Ensures correct execution flow during branch mispredictions.
Written entirely in SystemVerilog, with full verification.

Verification
The processor has been thoroughly tested using self-written testbenches in SystemVerilog. The verification process ensures:
Correct instruction execution
Proper hazard handling
Accurate branch prediction
Dependencies

Future Enhancements
Implement dynamic branch prediction
Support for out-of-order execution
Extend instruction set coverage

Credits
Processor Design & Verification: Maxwell Krieger
Memory & UIUC-Sourced Files: UIUC (These files not included)
