----------------------------------------------------------------------------------
-- Company: Trenz Electronic GmbH
-- Engineer: Mohsen Chamanbaz
-- 
-- Create Date: 15.09.2021 15:10:28
-- Design Name: 
-- Module Name: clk_divider - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- *********** Note : This code works only with even values of divider. **********
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity clk_divider is
    Port ( clk_in : in STD_LOGIC;
           reset  : in STD_LOGIC;
           divider : in STD_LOGIC_VECTOR (15 downto 0);
           clk_out : out STD_LOGIC);
end clk_divider;

architecture Behavioral of clk_divider is
    signal cnt : integer := 0;
    signal clock: std_logic := '0';
begin
    process(clk_in,reset)
    begin
        if reset = '0' then
            clock <= '0';
        elsif rising_edge(clk_in) then
            if cnt = to_integer(unsigned(divider)/2)-1 then
                clock <= not clock;
                cnt <= 0;
            else
                cnt <= cnt + 1;
            end if;
        end if;
    end process;  
         
clk_out <= clock;
                                 
end Behavioral;
