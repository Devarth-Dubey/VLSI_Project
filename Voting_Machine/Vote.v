module Vote(input clk,Power,Close,Clear,Ballot,Total,Result,input[3:0]IN, output reg[11:0] out);

    parameter s0=3'b000,s1=3'b001,s2=3'b010,s3=3'b011,s4=3'b100,s5=3'b101,s6=3'b110;
    reg[2:0] n,p;
    reg[3:0]i;
    reg[11:0] reg_b[15:0];
    reg lvl,lrl,lcl;
    integer m;
    
    always @(posedge  clk or posedge Power) 
	    if(clk)p<=n;
	    else p<=s0;
    always @*
                case(p)
                    s0:begin if(Clear)n=s5;
                             else begin 
                             		if(Close)n=s1;
                             		else begin 
		                     		if(Ballot)n=s2;
					    	else begin 
					    		if(Total)n=s3; 
				    			else n=s0;end
		    			     end 
		    		    end 
			end
                    s1:begin if(lcl) begin
		             			if(Result)n=s4;
		             			else n=s1;
                     			end 
                     	      else n=s0;end
                    s2:if(lvl)n=s2;else n=s0;
                    s3:if(Close||Ballot) n=s0; else n=s3;
                    s4:begin if(Clear)n=s5; else if(Result)n=s4;else n=s6;end
                    s5:if(Clear)n=s5; else n=s0;
                    s6:begin if(Clear)n=s5; else if(Result)n=s4; else n=s6;end
                    default: n=s0;
                endcase
                
    always @(posedge clk)           
            
            case(p)
                s0:begin if(Close)  begin  lcl<=1'b1;end
                            else if(Ballot) lvl<=1'b1;
                            else begin out<=12'b0;lcl<=1'b0;lvl<=1'b0;end
                    end
                s1:if(Result) lrl<=1'b1; else begin out<=12'b0;lrl<=1'b0; end
                s2:if( IN!=4'b0000 && lvl)begin 
                            reg_b[0] <=reg_b[0]+1;
                            reg_b[IN] <=reg_b[IN]+1;                                
                            lvl<=1'b0;
                            out<=12'b0; end
                    else begin out<=12'b0;
                                reg_b[IN] <=reg_b[IN];
                                reg_b[0] <=reg_b[0];
                                lvl<=lvl;
                        end
                s3:out<=reg_b[0];
                s4:begin 
                    if(lrl) begin
		            if(i!=4'b0)
		            out <= reg_b[i];
		            else out<=out;
		            i<=i+1;		            	            
		            end
		     else begin i<=i; out<=out; end		    
                    lrl<=1'b0;           
                    end
                s5:begin 
                        for(m=0;m<=15;m=m+1) begin
                        	reg_b[m]<=12'b0;
                        	end                     
                out<=12'b0;i<=4'b0000;lvl<=1'b0;lrl<=1'b0;lcl<=1'b0;
                   end
                s6:begin if(Result)lrl<=1'b1; else lrl<=1'b0;out<=out;end
            endcase
      
endmodule
