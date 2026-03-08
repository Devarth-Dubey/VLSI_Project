module mem_ctr(Data_in,clk,rst,read,write,hit,cach_dis); 
  input [9:0]Data_in; 
  input clk,rst; 
  input read,write; 
  output logic hit; 
  output logic [9:0]cache_dis; 
  reg [9:0] main_mem [6:0]; // 1K bit of size of each and total of 64 pages in main memoy 
  reg [9:0] cache_mem [2:0]; // 1K bit of size of each and total of 8 pages in main memoy 
  integer i,j,k,l; 
  integer pointer,index; 
   
  always @ (posedge clk or posedge rst) begin 
    if(rst) begin 
      for(i=0;i<2**7;i++)begin 
          main_mem[i]<=0; 
          cache_mem[i]<=0; 
          pointer<=0; 
          index<=0; 
        end 
    end 
    else if(write) begin 
      hit<=0; 
       for(j=0;j<2**3;j++) 
          if(cache_mem[j]==Data_in) hit<=1; 
          else hit<=0; 
         if(pointer<2**7) begin 
            main_mem[index]<=Data_in; 
            cache_mem[pointer]<=Data_in; 
            pointer++; 
            index++; 
        end 
        else begin 
          main_mem[index]<=Data_in; 
          for(k=2**3-2;k>=0;k--) begin 
            cache_mem[k]<=cache_mem[k+1]; 
          end 
          cache_mem[2**3-1]<=Data_in; 
        end 
      end 
    else begin 
    for(l=0;l<2**3;l++)begin 
            cache_dis<=cache_mem[l]; 
      end 
    end 
 end 
endmodule
