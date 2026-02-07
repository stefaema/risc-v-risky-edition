Here is the list of component functions, ordered by dependency depth (most independent first).

1. **`pc_reg_inst`**
* *Input:* `pipeline_status.if_id_status.program_counter_if`
* *Type:* State Reader


2. **`fixed_pc_adder_inst_if`**
* *Input:* `pipeline_status.if_id_status.program_counter_if`
* *Type:* Adder (Constant)


3. **`decoder_inst`**
* *Input:* `pipeline_status.if_id_status.instruction_if`
* *Type:* Logic (Bit extraction)


4. **`imm_gen_inst`**
* *Input:* `pipeline_status.if_id_status.instruction_if`
* *Type:* Logic (Bit extraction)


5. **`control_inst`**
* *Input:* `decoder_inst` (Opcode)
* *Type:* Logic (Lookup)


6. **`reg_file_inst`**
* *Input:* `pipeline_status.register_file`, `decoder_inst` (RS1/RS2 addr)
* *Type:* State Reader


7. **`forwarding_unit_inst`**
* *Input:* `pipeline_status.hazard_status` (Pre-calculated state)
* *Type:* State Extractor


8. **`hazard_protection_unit`**
* *Input:* `pipeline_status.hazard_status` (Pre-calculated state)
* *Type:* State Extractor


9. **`flow_controller_inst`**
* *Input:* `pipeline_status.hazard_status` (Pre-calculated state)
* *Type:* State Extractor


10. **`halt_unit_inst`**
* *Input:* `pipeline_status.id_ex_status.is_halt_id`
* *Type:* Logic


11. **`rs1_data_selector`**
* *Input:* `reg_file_inst`, `pipeline_status` (for forwarding values), `forwarding_unit_inst` (Select signal)
* *Type:* Mux


12. **`rs2_data_selector`**
* *Input:* `reg_file_inst`, `pipeline_status` (for forwarding values), `forwarding_unit_inst` (Select signal)
* *Type:* Mux


13. **`target_base_selector`**
* *Input:* `pipeline_status.if_id_status.pc_id`, `rs1_data_selector`, `control_inst` (is_jalr)
* *Type:* Mux


14. **`comparator`**
* *Input:* `rs1_data_selector`, `rs2_data_selector`
* *Type:* Logic (Arithmetic)


15. **`final_target_adder`**
* *Input:* `imm_gen_inst`, `target_base_selector`
* *Type:* Adder


16. **`pc_src_selector`**
* *Input:* `fixed_pc_adder_inst_if`, `final_target_adder`, `flow_controller_inst`
* *Type:* Mux


17. **`alu_ctrl_inst`**
* *Input:* `pipeline_status.id_ex_status` (Intent, Funct3, Funct7)
* *Type:* Logic


18. **`alu_src_selector`**
* *Input:* `pipeline_status.id_ex_status` (RS2, Imm, Select)
* *Type:* Mux


19. **`fixed_pc_adder_inst_ex`**
* *Input:* `pipeline_status.id_ex_status.pc_ex`
* *Type:* Adder (Constant)


20. **`alu_inst`**
* *Input:* `pipeline_status.id_ex_status.rs1_data_ex`, `alu_src_selector`, `alu_ctrl_inst`
* *Type:* Logic (Arithmetic)


21. **`rd_data_ex_selector`**
* *Input:* `alu_inst`, `fixed_pc_adder_inst_ex`, `pipeline_status.id_ex_status` (Select)
* *Type:* Mux


22. **`dmem_intf_inst`**
* *Input:* `pipeline_status.ex_mem_status` (Funct3, ALU Result, Store Data)
* *Type:* Logic (Mask generation)


23. **`rd_src_selector`**
* *Input:* `pipeline_status.mem_wb_status` (Execution Data, Memory Data, Select)
* *Type:* Mux
