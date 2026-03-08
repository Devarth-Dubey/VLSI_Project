module test; 
reg [9:0]Data_in; 
reg clk,rst,read,write; 
wire hit; 
wire [9:0] cach_dis; 
mem_ctr mem_lru(Data_in,clk,rst,read,write,hit,cach_dis); 
always #5 clk=~clk; 
initial begin 
clk=0;rst=0;read=0;write=0;Data_in=0; 
#5 rst=1; 
#3 rst=0; 
write=1; 
#6 
Data_in=32; 
#6 
write=0; 
#7 
write=1; 
#6 
Data_in=18; 
#6 
write=0; 
#7 
write=1; 
#6 
Data_in=47; 
#6 
write=0; 
#7 
    write=1; 
    #6 
    Data_in=51; 
    #6 
    write=0; 
    #7 
    write=1; 
    #6 
    Data_in=32; 
    #6 
    write=0; 
    #7 
    write=1; 
    #6 
    Data_in=24; 
    #6 
    write=0; 
    #7 
    write=1; 
    #6 
    Data_in=15; 
    #6 
    write=0; 
    #7 
    write=1; 
    #6 
Data_in=10; 
#6 
write=0; 
#7 
write=1; 
#6 
Data_in=49; 
#6 
write=0; 
#7 
write=1; 
#6 
Data_in=32; 
#6 
write=0; 
end 
initial begin 
$monitor("cach_mem=%d"mem_lru.cache_mem); 
end 
endmodule
