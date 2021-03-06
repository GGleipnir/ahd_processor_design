library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cpu is
   Port ( clk : in std_logic;
          rst : in std_logic);
end cpu;

architecture Behavioral of cpu is
    
    component ins_mem is
     Port ( inst : out STD_LOGIC_VECTOR (31 downto 0);
            addr : in STD_LOGIC_VECTOR (31 downto 0));
    end component;
    
    component ctrl_unit is
        Port ( lw : out STD_LOGIC;
               sw : out STD_LOGIC;
               branch : out STD_LOGIC;
               jump : out STD_LOGIC;
               funct : out STD_LOGIC_VECTOR (2 downto 0);
               op2src : out STD_LOGIC;
               regdst : out STD_LOGIC;
               regwrt : out STD_LOGIC;
               inst : in STD_LOGIC_VECTOR (31 downto 0));
    end component;
    
    component reg_file is
        Port ( rd1 : out STD_LOGIC_VECTOR (31 downto 0);
               rd2 : out STD_LOGIC_VECTOR (31 downto 0);
               clk : in STD_LOGIC;
               rst : in STD_LOGIC;
               we : in STD_LOGIC;
               rs : in STD_LOGIC_VECTOR (4 downto 0);
               rt : in STD_LOGIC_VECTOR (4 downto 0);
               rd : in STD_LOGIC_VECTOR (4 downto 0);
               wd : in STD_LOGIC_VECTOR (31 downto 0));
    end component;
    
    component alu is
        Port ( result : out STD_LOGIC_VECTOR (31 downto 0);
               eq : out STD_LOGIC;
               op1 : in STD_LOGIC_VECTOR (31 downto 0);
               op2 : in STD_LOGIC_VECTOR (31 downto 0);
               funct : in STD_LOGIC_VECTOR (2 downto 0));
    end component;
    
    component sign_ext is
        Port ( imm32 : out STD_LOGIC_VECTOR (31 downto 0);
               imm16 : in STD_LOGIC_VECTOR (15 downto 0));
    end component;
    
    component data_mem is
        Port ( rd : out STD_LOGIC_VECTOR (31 downto 0);
               clk : in STD_LOGIC;
               rst : in STD_LOGIC;
               we : in STD_LOGIC;
               addr : in STD_LOGIC_VECTOR (31 downto 0);
               wd : in STD_LOGIC_VECTOR (31 downto 0));
    end component;
    
    -- pc
    signal pc : unsigned (31 downto 0) := TO_UNSIGNED(0, 32);
    signal pc_pl4 : unsigned (31 downto 0);
    signal pc_offset : unsigned (31 downto 0);
    signal pc_addr : unsigned (25 downto 0);
    signal pc_src : std_logic_vector (1 downto 0);    
    
    -- instruction
    signal inst : std_logic_vector (31 downto 0);
    signal inst_opcode : std_logic_vector (5 downto 0);
    signal inst_rs : std_logic_vector (4 downto 0);
    signal inst_rt : std_logic_vector (4 downto 0);
    signal inst_rd : std_logic_vector (4 downto 0);
    signal inst_funct : std_logic_vector (5 downto 0);
    signal inst_imm : std_logic_vector (15 downto 0);
    signal inst_addr : std_logic_vector (25 downto 0);
    
    -- control signals
    signal ctrl_lw : std_logic;
    signal ctrl_sw : std_logic;
    signal ctrl_branch : std_logic;
    signal ctrl_jump : std_logic;
    signal ctrl_funct : std_logic_vector (2 downto 0);
    signal ctrl_op2src : std_logic;
    signal ctrl_regdst : std_logic;
    signal ctrl_regwrt : std_logic;
    
    -- register file
    signal reg_rd1 : std_logic_vector (31 downto 0);
    signal reg_rd2 : std_logic_vector (31 downto 0);
    signal reg_wd : std_logic_vector (31 downto 0);
    signal reg_dst : std_logic_vector (4 downto 0);
    
    -- alu
    signal imm_sign_ext : std_logic_vector (31 downto 0);
    signal alu_op2 : std_logic_vector (31 downto 0);
    signal alu_result : std_logic_vector (31 downto 0);
    signal alu_eq : std_logic;
    
    -- data memory
    signal mem_rd : std_logic_vector (31 downto 0);    

begin

    -- pc
    pc_pl4 <= pc + 4;
    pc_offset <= UNSIGNED(imm_sign_ext(29 downto 0)&"00");
    pc_addr <= UNSIGNED(inst_addr);
    pc_src(0) <= ctrl_jump;
    pc_src(1) <= (ctrl_branch and alu_eq) or (ctrl_branch and ctrl_jump);
    
    PC_SYNC : process(clk, rst)
    begin
        if (rst = '1') then 
            pc <= TO_UNSIGNED(0, 32);
        elsif rising_edge(clk) then
            case pc_src is
                when "00" =>                    -- next inst
                    pc <= pc_pl4;                              
                when "01" =>                    -- jump
                    pc <= pc_pl4(31 downto 28) & pc_addr & "00";
                when "10" =>                    -- branch
                    pc <= pc_offset + pc_pl4;
                when others =>                  -- halt
                    pc <= pc;
            end case;
        end if;
    end process;
    
    -- inst decompose
    inst_opcode <= inst(31 downto 26);
    inst_rs <= inst(25 downto 21);
    inst_rt <= inst(20 downto 16);
    inst_rd <= inst(15 downto 11);
    inst_funct <= inst(5 downto 0);
    inst_imm <= inst(15 downto 0);
    inst_addr <= inst(25 downto 0);
    
    -- inst mem
    U_ins_mem : ins_mem 
       port map ( inst => inst,
                  addr => std_logic_vector(pc));
    
    U_ctrl_unit : ctrl_unit
        port map ( lw => ctrl_lw,
                   sw => ctrl_sw,
                   branch => ctrl_branch,
                   jump => ctrl_jump,
                   funct => ctrl_funct,
                   op2src => ctrl_op2src,
                   regdst => ctrl_regdst,
                   regwrt => ctrl_regwrt,
                   inst => inst);
    
    with ctrl_regdst select reg_dst <= inst_rd when '1', inst_rt when others;
    U_reg_file : reg_file
        port map ( rd1 => reg_rd1,
                   rd2 => reg_rd2,
                   clk => clk,
                   rst => rst,
                   we => ctrl_regwrt,
                   rs => inst_rs,
                   rt => inst_rt,
                   rd => reg_dst,
                   wd => reg_wd);
                   
    with ctrl_op2src select alu_op2 <= imm_sign_ext when '1', reg_rd2 when others;
    U_alu : alu 
        port map ( result => alu_result,
                   eq => alu_eq,
                   op1 => reg_rd1,
                   op2 => alu_op2,
                   funct => ctrl_funct);
                   
    U_sign_ext : sign_ext
        port map ( imm32 => imm_sign_ext,
                   imm16 => inst_imm);
                   
    U_data_mem : data_mem
        port map ( rd => mem_rd,
                   clk => clk,
                   rst => rst,
                   we => ctrl_sw,
                   addr => alu_result,
                   wd => reg_rd2);
    
    with ctrl_lw select reg_wd <= mem_rd when '1', alu_result when others;

end Behavioral;
