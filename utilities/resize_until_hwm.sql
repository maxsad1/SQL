/****************************************************************************************************
 * Purpose: to resize datafiles until High water mark
 *
 * Parameters:
 * Operation Mode: Set v_report to TRUE for reporting mode, set v_execute_cmd to TRUE if you want to execute also
 * Author: Anjul Sahu
 * 
 * History:
 * 1.0		Anjul Sahu		03-Oct-2014		Initial Version
 *****************************************************************************************************/



set lines 300
set serverout on;
DECLARE
v_blk_size NUMBER:=8192;
v_extra_coeff number:=1.10; /* for adding 10 percent after HWM */
v_new_size number;
v_sql_cmd varchar2(1000);
v_report boolean := true; 
v_execute_cmd boolean := false;
BEGIN
dbms_output.enable(100000);
-- get block size of the database
select value INTO v_blk_size 
from v$parameter 
where name = 'db_block_size';

dbms_output.put_line(rpad('TABLESPACE_NAME',20,' ')||rpad('FILE_NAME',64,' ')||lpad('SMALLEST(M)',15,' ')||lpad('CURRSIZE(M)',15,' ')||lpad('MAXSIZE(M)',15,' ')||lpad('SAVINGS(M)',15,' '));
dbms_output.put_line('-----------------------------------------------------------------------------------------------------------------------------------------------');
FOR c_report IN (
	select tablespace_name, 
	   file_name, 
	   autoextensible,
	   ceil(maxbytes/1024/1024) maxsize,
       ceil( (nvl(hwm,1)*v_blk_size)/1024/1024 ) smallest,
       ceil( blocks*v_blk_size/1024/1024) currsize,
       ceil( blocks*v_blk_size/1024/1024) -
       ceil( (nvl(hwm,1)*v_blk_size)/1024/1024 ) savings
from dba_data_files a,
     ( select file_id, max(block_id+blocks-1) hwm
         from dba_extents
        group by file_id ) b
where a.file_id = b.file_id(+)
and a.tablespace_name not in ('SYSTEM','SYSAUX','AUDIT1'))
loop
    dbms_output.put_line(rpad(c_report.tablespace_name,20,' ')||rpad(c_report.file_name,64,' ')||lpad(c_report.smallest,15,' ')||lpad(c_report.currsize,15,' ')||lpad(c_report.maxsize,15,' ')||lpad(c_report.savings,15,' '));
    
    v_new_size := ceil(c_report.smallest * v_extra_coeff);
    
    IF (c_report.currsize < v_new_size) THEN
        v_new_size := c_report.currsize; 
    END IF;
       
    IF (v_execute_cmd = TRUE) THEN
	BEGIN
		IF (c_report.maxsize>c_report.currsize AND c_report.AUTOEXTENSIBLE='YES' AND c_report.maxsize<32000) THEN /* 32000 to handle unlimited autoextend size */
		v_sql_cmd:='alter database datafile '''||c_report.file_name ||''' autoextend on maxsize '||c_report.maxsize||'M';
		ELSE
		v_sql_cmd:='alter database datafile '''||c_report.file_name ||''' autoextend on maxsize '||c_report.currsize||'M';
		END IF;
		dbms_output.put_line(v_sql_cmd);
		EXECUTE IMMEDIATE v_sql_cmd;
		
		
		v_sql_cmd:='alter database datafile '''||c_report.file_name ||''' resize '||v_new_size ||'M';
		dbms_output.put_line(v_sql_cmd);
		EXECUTE IMMEDIATE v_sql_cmd;
		EXCEPTION
			WHEN OTHERS THEN
				DBMS_OUTPUT.PUT_LINE('Error occurred '||SQLERRM);
		END;
		
	END IF;
	
end loop; 


EXCEPTION
		WHEN OTHERS THEN
			DBMS_OUTPUT.PUT_LINE('Error occurred '||SQLERRM);
END;
/