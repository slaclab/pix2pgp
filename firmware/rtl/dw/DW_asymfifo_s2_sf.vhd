-- pix2pgp stub file

library IEEE;
use IEEE.std_logic_1164.all;
entity DW_asymfifo_s2_sf is

   generic (
          data_in_width  : INTEGER  ;
          data_out_width : INTEGER  ;
          depth : INTEGER  := 8;
          push_ae_lvl : INTEGER  := 2;
          push_af_lvl : INTEGER  := 2;
          pop_ae_lvl : INTEGER  := 2;
          pop_af_lvl : INTEGER  := 2;
          err_mode : INTEGER  := 0;
          push_sync : INTEGER  := 2;
          pop_sync : INTEGER  := 2;
          rst_mode : INTEGER  := 1;
          byte_order : INTEGER  := 0
      );

   port    (
          clk_push : in std_logic;
          clk_pop : in std_logic;
          rst_n : in std_logic;
          push_req_n : in std_logic;
          flush_n : in std_logic;
          pop_req_n : in std_logic;
          data_in : in std_logic_vector(data_in_width-1 downto 0);
          push_empty : out std_logic;
          push_ae : out std_logic;
          push_hf : out std_logic;
          push_af : out std_logic;
          push_full : out std_logic;
          ram_full : out std_logic;
          part_wd : out std_logic;
          push_error : out std_logic;
          pop_empty : out std_logic;
          pop_ae : out std_logic;
          pop_hf : out std_logic;
          pop_af : out std_logic;
          pop_full : out std_logic;
          pop_error : out std_logic;
          data_out : out std_logic_vector(data_out_width-1 downto 0 )
      );
end DW_asymfifo_s2_sf;

architecture stub of DW_asymfifo_s2_sf is

begin

end stub;
