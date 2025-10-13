--
-- Name: panier; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE panier (
    client integer NOT NULL,
    produit integer NOT NULL,
    PRIMARY KEY (client, produit)
);


--
-- Name: produit; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE produit (
    id integer PRIMARY KEY,
    nom character varying(255),
    prix integer,
    CONSTRAINT produit_prix_check CHECK (prix > 0)
);

--
-- Data for Name: panier; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO panier (client, produit) VALUES
(0, 0),
(1,0);


--
-- Data for Name: produit; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO produit (id, nom, prix) VALUES
(0, 'pommes', 5),
(1, 'poires', 5),
(2,'carottes',2),
(3,'bananes',1),
(4,'tomates',4);

--
-- PostgreSQL database dump complete
--

