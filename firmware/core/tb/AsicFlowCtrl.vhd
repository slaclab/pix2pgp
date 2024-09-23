library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library surf;
use surf.StdRtlPkg.all;

library pix2pgp;
use pix2pgp.Pix2PgpPkg.all;

entity AsicFlowCtrl is
   generic(
      TPD_G           : time     := 1 ns;
      RST_ASYNC_G     : boolean  := false;
      RST_POLARITY_G  : sl       := '1');
    port (
        clk           : in  sl;
        rst           : in  sl;
        sro           : in  sl;
        tokFb         : in  sl;
        sparseItfBusy : in  sl;
        pix2pgpBusy   : in  sl;
        sof           : out sl;
        eof           : out sl;
        overOcc       : out sl
    );
end entity;

architecture behavioral of AsicFlowCtrl is

    type state_type is (IDLE_S, WAIT_PIX2PGP_S, IN_FRAME_S, IN_OVEROCC_S);
    signal state         : state_type := IDLE_S;
    signal sro_dly       : sl := '0';
    signal sro_posedge   : sl := '0';
    signal tokFb_dly     : sl := '0';
    signal tokFb_negedge : sl := '0';

begin
   process(clk)
   begin
       if rising_edge(clk) then
           tokFb_dly <= tokFb;
       end if;
   end process;

   tokFb_negedge <= not(tokFb) and tokFb_dly;

    process(clk)
    begin
        if rising_edge(clk) then
            sro_dly <= sro;
        end if;
    end process;

    sro_posedge <= sro and not sro_dly;

    process(clk, rst)
    begin
        if rst = RST_POLARITY_G then
            state   <= IDLE_S;
            sof     <= '0';
            eof     <= '0';
            overOcc <= '0';
        elsif rising_edge(clk) then
            case state is
                when IDLE_S =>
                    if tokFb_negedge = '1' and pix2pgpBusy = '0' then
                        sof   <= '1'            after TPD_G;
                        state <= WAIT_PIX2PGP_S after TPD_G;
                    end if;

                    -- missed handshaking; if still busy, issue eof
                    eof <= pix2pgpBusy;

                when WAIT_PIX2PGP_S =>
                    if pix2pgpBusy = '1' then
                        sof   <= '0'        after TPD_G;
                        state <= IN_FRAME_S after TPD_G;
                    end if;

                when IN_FRAME_S =>
                    if sro_posedge = '1' then
                        eof     <= '0'          after TPD_G;
                        overOcc <= '1'          after TPD_G;
                        state   <= IN_OVEROCC_S after TPD_G;
                    elsif tokFb_dly = '1' and sparseItfBusy = '0' then
                        eof     <= '1'    after TPD_G;
                        overOcc <= '0'    after TPD_G;
                        state   <= IDLE_S after TPD_G;
                    end if;

                when IN_OVEROCC_S =>
                    overOcc <= '0' after TPD_G;
                    if tokFb_negedge = '1' then
                        state <= IN_FRAME_S after TPD_G;
                    end if;

                when others =>
                    state <= IDLE_S after TPD_G;
            end case;
        end if;
    end process;

end architecture;
