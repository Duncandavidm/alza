import { redirect } from "next/navigation";

// "Bonos y regalos" ahora es "Cupones > Regalar cupones".
export default function BonosPage() {
  redirect("/cupones/regalar");
}
