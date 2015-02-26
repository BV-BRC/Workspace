import org.patricbrc.Workspace.*;
import java.util.Arrays;
import java.util.List;
import java.util.Map;

public class ex
{
    public static void main(String args[])
    {
	try {
	    String token = "un=olson|tokenid=2A8BCAFA-ACBA-11E4-A91B-68C642A49C03|expiry=1454623630|client_id=olson|token_type=Bearer|SigningSubject=http://rast.nmpdr.org/goauth/keys/E087E220-F8B1-11E3-9175-BD9D42A49C03|this_is_globus=globus_style_token|sig=03a3cfae05a8dbaaaf57e34eb4800bc8b3c8046beb18620a8d605867490228302651f050578a7dd30181366b1cf7170dedc89a45a6b41a3ce6ebd96069834be090281c2bf4f3917a005a63f5ac78799843d33b690cfc76f7d59ef846fe7a23d5d623d830584d23adad60293cb56d250ed8c1c3169e8fdaf89bfc7c3f50bdaf9d";

	    Workspace w = new Workspace("http://p3.theseed.org/services/Workspace", token);

	    get_params getpar = new get_params();
	    getpar.objects = Arrays.asList("/olson/olson/prefs.json");
	    getpar.metadata_only = 0;
	    getpar.adminmode = 0;
	    List<Workspace_tuple_2> getres = w.get(getpar);
	    System.out.println(getres.get(0).e_2);

	    Map<String, List<ObjectMeta>> res;
	    list_params lp = new list_params();
	    lp.paths = Arrays.asList("/olson/olson");
	    res = w.ls(lp);
	    System.out.println(res.entrySet());

	    get_params gp = new get_params();
	    gp.objects = Arrays.asList("/olson/olson/Makefile3");
	    gp.metadata_only = 0;
	    gp.adminmode = 0;
	    
	    List<Workspace_tuple_2> r = w.get(gp);
	    System.out.println(r.get(0).e_2);
	} catch (Exception e)
	{
	    System.out.println("Failure: " + e);
	}
    }
}